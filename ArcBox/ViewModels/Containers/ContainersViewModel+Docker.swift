import ArcBoxClient
import DockerClient
import Foundation
import os

extension ContainersViewModel {
    // MARK: - Docker API Operations

    /// Load containers from Docker Engine API.
    func loadContainersFromDocker(docker: DockerClient?, iconClient: ArcBoxClient? = nil) async {
        guard let docker else {
            Log.container.debug("No docker client available")
            return
        }

        await listLoadGate.run {
            await self.performLoadContainersFromDocker(docker: docker, iconClient: iconClient)
        }
    }

    private func performLoadContainersFromDocker(
        docker: DockerClient,
        iconClient: ArcBoxClient?
    ) async {
        let isRefresh = loadState.beginLoading()

        let currentTransitioning = transitioningIDs
        let cachedDetails = containerDetailsCache()
        do {
            let containerList = try await Perf.measure("container.list_docker") {
                let response = try await docker.api.ContainerList(.init(query: .init(all: true)))
                return try response.ok.body.json
            }
            var viewModels = containerList.map { ContainerViewModel(fromDocker: $0) }
            applyCachedDetails(cachedDetails, to: &viewModels)
            applyCachedIcons(to: &viewModels)
            for i in viewModels.indices where currentTransitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            containers = viewModels
            Log.container.info("Loaded \(self.containers.count, privacy: .public) containers via Docker")
            applyExpandedGroups(from: containers)
            await fetchIcons(client: iconClient)
            if let selectedID, containers.contains(where: { $0.id == selectedID }) {
                await loadContainerDetailsFromDocker(selectedID, docker: docker)
            }
            loadState = .loaded
            refreshError = nil
            lastSuccessfulListLoad = ContinuousClock().now
        } catch {
            if loadState.cancelLoading(for: error, retainingLoadedContent: isRefresh) {
                return
            }
            Log.container.error("Error loading containers: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "list_docker")
            refreshError = loadState.fail(
                error.localizedDescription,
                retainingLoadedContent: isRefresh
            )
        }
    }

    @discardableResult
    func startContainerDocker(_ id: String, docker: DockerClient?) async -> Bool {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return false
        }
        setTransitioning(id, true)
        var succeeded = false
        do {
            let response = try await docker.api.ContainerStart(path: .init(id: id))
            if let message = response.startFailureMessage {
                lastError = message
            } else {
                setContainerRunningState(id, isRunning: true)
                succeeded = true
                Analytics.capture(.containerStarted, properties: ["backend": "docker", "batch": false])
            }
        } catch {
            Log.container.error(
                "Error starting container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "start_docker")
            lastError = error.localizedDescription
        }
        setTransitioning(id, false)
        await loadContainersFromDocker(docker: docker)
        return succeeded
    }

    func stopContainerDocker(_ id: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }
        setTransitioning(id, true)
        do {
            let response = try await docker.api.ContainerStop(path: .init(id: id))
            if let message = response.stopFailureMessage {
                lastError = message
            } else {
                setContainerRunningState(id, isRunning: false)
                Analytics.capture(.containerStopped, properties: ["backend": "docker", "batch": false])
            }
        } catch {
            Log.container.error(
                "Error stopping container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "stop_docker")
            lastError = error.localizedDescription
        }
        setTransitioning(id, false)
        await loadContainersFromDocker(docker: docker)
    }

    func removeContainerDocker(_ id: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }
        do {
            let response = try await docker.api.ContainerDelete(path: .init(id: id), query: .init(force: true))
            if let message = response.deleteFailureMessage {
                lastError = message
            } else {
                removeContainerLocally(id)
                Analytics.capture(.containerRemoved, properties: ["backend": "docker", "batch": false])
                NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
            }
        } catch {
            Log.container.error(
                "Error removing container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "remove_docker")
            lastError = error.localizedDescription
        }
        await loadContainersFromDocker(docker: docker)
    }

    func loadContainerDetailsFromDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }

        do {
            // Prefer raw snapshot to avoid date decoding failures and to support
            // NetworkSettings.Networks.*.IPAddress fallback consistently.
            let snapshot = try await docker.inspectContainerSnapshot(id: id)
            let mounts = snapshot.mounts.compactMap { mount -> ContainerMount? in
                guard let destination = Self.normalized(mount.destination) else { return nil }
                let source = Self.normalized(mount.source) ?? "-"
                return ContainerMount(
                    type: Self.normalized(mount.type) ?? "unknown",
                    source: source,
                    destination: destination,
                    isReadOnly: !(mount.rw ?? true)
                )
            }
            setContainerDetails(
                id,
                domain: Self.normalized(snapshot.domainname),
                ipAddress: Self.normalized(snapshot.ipAddress),
                mounts: mounts,
                rootfsMountPath: Self.normalized(snapshot.rootfsMountPath)
            )
            let snapshotDomain = Self.normalized(snapshot.domainname) ?? "-"
            let snapshotIP = Self.normalized(snapshot.ipAddress) ?? "-"
            let snapshotRootFS = Self.normalized(snapshot.rootfsMountPath) ?? "-"
            Log.container.debug("Inspect snapshot for \(id, privacy: .private)")
            Log.container.debug(
                "domain=\(snapshotDomain, privacy: .private), ip=\(snapshotIP, privacy: .private), mounts=\(mounts.count, privacy: .public)"
            )
            Log.container.debug(
                "rootfs=\(snapshotRootFS, privacy: .private)"
            )
        } catch {
            Log.container.error(
                "Inspect snapshot failed for \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            do {
                // Fallback to generated inspect model if raw path fails unexpectedly.
                let response = try await docker.api.ContainerInspect(path: .init(id: id))
                let details = try response.ok.body.json

                let mounts = (details.Mounts ?? []).compactMap { mount -> ContainerMount? in
                    guard let destination = Self.normalized(mount.Destination) else { return nil }
                    let source = Self.normalized(mount.Source) ?? "-"
                    return ContainerMount(
                        type: "unknown",
                        source: source,
                        destination: destination,
                        isReadOnly: false
                    )
                }

                setContainerDetails(
                    id,
                    domain: Self.normalized(details.Config?.Domainname),
                    ipAddress: Self.normalized(details.NetworkSettings?.IPAddress),
                    mounts: mounts
                )
                let fallbackDomain = Self.normalized(details.Config?.Domainname) ?? "-"
                let fallbackIP = Self.normalized(details.NetworkSettings?.IPAddress) ?? "-"
                Log.container.debug("Inspect fallback for \(id, privacy: .private)")
                Log.container.debug(
                    "domain=\(fallbackDomain, privacy: .private), ip=\(fallbackIP, privacy: .private), mounts=\(mounts.count, privacy: .public)"
                )
            } catch {
                Log.container.error(
                    "Inspect fallback failed for \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                )
                ErrorReporting.capture(error, domain: .container, operation: "inspect_docker")
            }
        }
    }
}

extension Operations.ContainerStart.Output {
    nonisolated var startFailureMessage: String? {
        switch self {
        case .noContent, .notModified:
            nil
        case .notFound(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Container not found."
            }
        case .internalServerError(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Docker failed to start the container."
            }
        case .undocumented(let statusCode, _):
            "Unexpected response status \(statusCode)."
        }
    }
}

extension Operations.ContainerStop.Output {
    nonisolated var stopFailureMessage: String? {
        switch self {
        case .noContent, .notModified:
            nil
        case .notFound(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Container not found."
            }
        case .internalServerError(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Docker failed to stop the container."
            }
        case .undocumented(let statusCode, _):
            "Unexpected response status \(statusCode)."
        }
    }
}

extension Operations.ContainerDelete.Output {
    nonisolated var deleteFailureMessage: String? {
        switch self {
        case .noContent:
            nil
        case .badRequest(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Docker rejected the container removal request."
            }
        case .notFound(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Container not found."
            }
        case .conflict(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Docker could not remove the container due to a conflict."
            }
        case .internalServerError(let response):
            switch response.body {
            case .json(let error):
                error.message
            case .plainText:
                "Docker failed to remove the container."
            }
        case .undocumented(let statusCode, _):
            "Unexpected response status \(statusCode)."
        }
    }
}
