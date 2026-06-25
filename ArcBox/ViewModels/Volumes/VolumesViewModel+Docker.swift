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

        do {
            let response = try await docker.api.SystemDataUsage(query: .init(_type: [.volume]))
            let dfResponse = try response.ok.body.json
            volumes = (dfResponse.Volumes ?? []).map { VolumeViewModel(fromDocker: $0) }
            Log.volume.info("Loaded \(self.volumes.count, privacy: .public) volumes")
        } catch {
            Log.volume.error("Error loading volumes: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "list")
        }
    }

    /// Create a volume. Returns true on success.
    func createVolume(name: String, docker: DockerClient?) async -> Bool {
        guard let docker else { return false }
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
            return false
        }
    }

    /// Ensure a helper image exists locally, pulling it on demand if necessary.
    func ensureImageExists(_ image: String, docker: DockerClient) async throws {
        // Check if image exists locally
        do {
            _ = try await docker.api.ImageInspect(path: .init(name: image))
            return
        } catch {}
        // Pull it
        let response = try await docker.api.ImageCreate(query: .init(fromImage: image))
        _ = try response.ok
    }

    /// Import a tar archive into a new volume. Returns true on success.
    /// Creates the volume, then uses a temporary container + PutContainerArchive to extract contents.
    func importVolume(name: String, tarURL: URL, docker: DockerClient?) async -> Bool {
        guard let docker else { return false }

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
            return false
        }

        // Helper to clean up the volume on failure
        var success = false
        defer {
            if !success {
                Task {
                    _ = try? await docker.api.VolumeDelete(path: .init(name: volName), query: .init(force: true))
                }
            }
        }

        // 2. Ensure busybox image exists
        do {
            try await ensureImageExists("busybox:latest", docker: docker)
        } catch {
            Log.volume.error("Error pulling busybox for import: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "import_pull_helper")
            return false
        }

        // 3. Create temp container with volume mounted
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
                                value2: .init(Binds: ["\(volName):/data"])
                            ))
                    ))
            )
            tempID = try response.created.body.json.Id
        } catch {
            Log.volume.error(
                "Error creating temp container for import: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "import_container")
            return false
        }

        // 4. Upload tar into /data
        defer {
            Task {
                _ = try? await docker.api.ContainerDelete(path: .init(id: tempID), query: .init(force: true))
            }
        }
        do {
            let data = try Data(contentsOf: tarURL, options: .mappedIfSafe)
            let body = HTTPBody(data)
            let response = try await docker.api.PutContainerArchive(
                path: .init(id: tempID),
                query: .init(path: "/data"),
                body: .application_x_hyphen_tar(body)
            )
            _ = try response.ok
            Log.volume.info("Imported tar into volume \(volName, privacy: .private)")
        } catch {
            Log.volume.error("Error importing tar into volume: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "import_upload")
            return false
        }

        success = true
        await loadVolumes(docker: docker)
        return true
    }

    func removeVolume(_ name: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else { return }
        if selectedID == name { selectedID = nil }
        do {
            let response = try await docker.api.VolumeDelete(path: .init(name: name), query: .init(force: true))
            _ = try response.noContent
            Log.volume.info("Removed volume \(name, privacy: .private)")
        } catch {
            Log.volume.error(
                "Error removing volume \(name, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .volume, operation: "remove")
            lastError = error.localizedDescription
        }
        await loadVolumes(docker: docker)
    }
}
