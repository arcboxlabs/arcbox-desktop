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

        if loadState != .loaded {
            loadState = .loading
        }

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
        } catch {
            Log.container.error("Error loading containers: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "list_docker")
            if containers.isEmpty {
                loadState = .failed(error.localizedDescription)
            } else {
                loadState = .loaded
                lastError = error.localizedDescription
            }
        }
    }

    func startContainerDocker(_ id: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else { return }
        setTransitioning(id, true)
        do {
            _ = try await docker.api.ContainerStart(path: .init(id: id))
            setContainerRunningState(id, isRunning: true)
        } catch {
            Log.container.error(
                "Error starting container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "start_docker")
            lastError = error.localizedDescription
        }
        setTransitioning(id, false)
        await loadContainersFromDocker(docker: docker)
    }

    func stopContainerDocker(_ id: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else { return }
        setTransitioning(id, true)
        do {
            _ = try await docker.api.ContainerStop(path: .init(id: id))
            setContainerRunningState(id, isRunning: false)
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
        guard let docker else { return }
        do {
            _ = try await docker.api.ContainerDelete(path: .init(id: id), query: .init(force: true))
            removeContainerLocally(id)
            NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
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
