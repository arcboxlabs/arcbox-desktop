import DockerClient
import Foundation
import OSLog
import OpenAPIRuntime

extension VolumesViewModel {
    /// Load volumes from Docker Engine API using system disk usage endpoint
    /// to include volume size information.
    func loadVolumes(docker: DockerClient?) async {
        guard let docker else {
            Log.volume.debug("No docker client available")
            return
        }

        await listLoadGate.run {
            await self.performLoadVolumes(docker: docker)
        }
    }

    private func performLoadVolumes(docker: DockerClient) async {
        let isRefresh = loadState.beginLoading()
        do {
            let response = try await docker.api.SystemDataUsage(query: .init(_type: [.volume]))
            let dfResponse = try response.ok.body.json
            volumes = (dfResponse.Volumes ?? []).map { VolumeViewModel(fromDocker: $0) }
            Log.volume.info("Loaded \(self.volumes.count, privacy: .public) volumes")
            loadState = .loaded
            refreshError = nil
            lastSuccessfulListLoad = ContinuousClock().now
        } catch {
            if loadState.cancelLoading(for: error, retainingLoadedContent: isRefresh) {
                return
            }
            Log.volume.error("Error loading volumes: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "list")
            refreshError = loadState.fail(
                error.localizedDescription,
                retainingLoadedContent: isRefresh
            )
        }
    }

    /// Create a volume. Returns true on success.
    func createVolume(name: String, docker: DockerClient?) async -> Bool {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return false
        }
        do {
            let response = try await docker.api.VolumeCreate(
                body: .json(.init(Name: name.isEmpty ? nil : name))
            )
            let vol = try response.created.body.json
            Log.volume.info("Created volume \(vol.Name, privacy: .private)")
            await loadVolumes(docker: docker)
            return true
        } catch {
            Log.volume.error("Error creating volume: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "create")
            lastError = error.localizedDescription
            return false
        }
    }

    /// Ensure a helper image exists locally, pulling it on demand if necessary.
    func ensureImageExists(_ image: String, docker: DockerClient) async throws {
        // Check if image exists locally
        let inspect = try await docker.api.ImageInspect(path: .init(name: image))
        switch inspect {
        case .ok:
            return
        case .notFound:
            break
        default:
            _ = try inspect.ok
        }

        // Pull it
        let response = try await docker.api.ImageCreate(query: .init(fromImage: image))
        _ = try response.ok
    }

    /// Import a tar archive into a new volume. Returns true on success.
    /// Creates the volume, then uses a temporary container + PutContainerArchive to extract contents.
    func importVolume(name: String, tarURL: URL, docker: DockerClient?) async -> Bool {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return false
        }

        // 1. Create volume
        let volName: String
        do {
            let response = try await docker.api.VolumeCreate(
                body: .json(.init(Name: name.isEmpty ? nil : name))
            )
            volName = try response.created.body.json.Name
        } catch {
            Log.volume.error("Error creating volume for import: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "import_create")
            lastError = error.localizedDescription
            return false
        }

        // 2-4. Populate it. `defer` cannot await, so cleanup is sequenced explicitly here:
        // a fire-and-forget Task can be discarded before it runs, orphaning the volume.
        do {
            try await fill(volume: volName, from: tarURL, docker: docker)
        } catch {
            _ = try? await docker.api.VolumeDelete(
                path: .init(name: volName), query: .init(force: true))
            lastError = error.localizedDescription
            return false
        }

        Log.volume.info("Imported tar into volume \(volName, privacy: .private)")
        await loadVolumes(docker: docker)
        return true
    }

    /// Extract `tarURL` into `volume` through a temporary container, which is removed on both
    /// the success and the failure path before this returns.
    private func fill(volume: String, from tarURL: URL, docker: DockerClient) async throws {
        do {
            try await ensureImageExists("busybox:latest", docker: docker)
        } catch {
            Log.volume.error("Error pulling busybox for import: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "import_pull_helper")
            throw error
        }

        var config = Components.Schemas.ContainerConfig()
        config.Image = "busybox:latest"
        config.Cmd = ["true"]

        let tempID: String
        do {
            let response = try await docker.api.ContainerCreate(
                body: .json(
                    .init(
                        value1: config,
                        value2: .init(
                            HostConfig: .init(
                                value1: .init(),
                                value2: .init(Binds: ["\(volume):/data"])
                            ))
                    ))
            )
            tempID = try response.created.body.json.Id
        } catch {
            Log.volume.error(
                "Error creating temp container for import: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "import_container")
            throw error
        }

        let outcome: Result<Void, any Error>
        do {
            let data = try Data(contentsOf: tarURL, options: .mappedIfSafe)
            let response = try await docker.api.PutContainerArchive(
                path: .init(id: tempID),
                query: .init(path: "/data"),
                body: .application_x_hyphen_tar(HTTPBody(data))
            )
            _ = try response.ok
            outcome = .success(())
        } catch {
            Log.volume.error("Error importing tar into volume: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "import_upload")
            outcome = .failure(error)
        }

        _ = try? await docker.api.ContainerDelete(path: .init(id: tempID), query: .init(force: true))
        try outcome.get()
    }

    func removeVolume(_ name: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }
        do {
            let response = try await docker.api.VolumeDelete(path: .init(name: name), query: .init(force: true))
            if applyVolumeDeletion(response, name: name) {
                Log.volume.info("Removed volume \(name, privacy: .private)")
            }
        } catch {
            Log.volume.error(
                "Error removing volume \(name, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "remove")
            lastError = error.localizedDescription
        }
        await loadVolumes(docker: docker)
    }

    @discardableResult
    func applyVolumeDeletion(_ response: Operations.VolumeDelete.Output, name: String) -> Bool {
        if let message = response.deleteFailureMessage {
            lastError = message
            return false
        }
        if selectedID == name { selectedID = nil }
        return true
    }
}

extension Operations.VolumeDelete.Output {
    nonisolated var deleteFailureMessage: String? {
        switch self {
        case .noContent:
            nil
        case .notFound(let response):
            switch response.body {
            case .json(let error): error.message
            case .plainText: "Volume not found."
            }
        case .conflict(let response):
            switch response.body {
            case .json(let error): error.message
            case .plainText: "Docker cannot remove a volume that is in use."
            }
        case .internalServerError(let response):
            switch response.body {
            case .json(let error): error.message
            case .plainText: "Docker failed to remove the volume."
            }
        case .undocumented(let statusCode, _):
            "Unexpected response status \(statusCode)."
        }
    }
}
