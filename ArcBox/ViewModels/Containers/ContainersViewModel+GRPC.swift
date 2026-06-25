import ArcBoxClient
import DockerClient
import Foundation
import os

extension ContainersViewModel {
    // MARK: - gRPC Operations

    /// Load containers from daemon via gRPC.
    func loadContainers(client: ArcBoxClient?) async {
        guard let client else {
            Log.container.debug("No gRPC client available")
            return
        }

        let currentTransitioning = transitioningIDs
        let cachedDetails = containerDetailsCache()
        do {
            var request = Arcbox_V1_ListContainersRequest()
            request.all = true
            let listRequest = request
            let response = try await Perf.measure("container.list_grpc") {
                try await client.containers.list(listRequest, options: ArcBoxClient.defaultCallOptions)
            }
            var viewModels = response.containers.map { summary in
                ContainerViewModel(from: summary)
            }
            applyCachedDetails(cachedDetails, to: &viewModels)
            applyCachedIcons(to: &viewModels)
            for i in viewModels.indices where currentTransitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            containers = viewModels
            applyExpandedGroups(from: containers)
            await fetchIcons(client: client)
            if let selectedID, containers.contains(where: { $0.id == selectedID }) {
                await loadContainerDetails(selectedID, client: client)
            }
        } catch {
            Log.container.error("Error loading containers via gRPC: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "list_grpc")
        }
    }

    func startContainer(_ id: String, client: ArcBoxClient?) async {
        lastError = nil
        guard let client else { return }
        setTransitioning(id, true)
        var request = Arcbox_V1_StartContainerRequest()
        request.id = id
        do {
            _ = try await client.containers.start(request, options: ArcBoxClient.defaultCallOptions)
            setContainerRunningState(id, isRunning: true)
        } catch {
            Log.container.error(
                "Error starting container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "start")
            lastError = error.localizedDescription
        }
        setTransitioning(id, false)
        await loadContainers(client: client)
    }

    func stopContainer(_ id: String, client: ArcBoxClient?) async {
        lastError = nil
        guard let client else { return }
        setTransitioning(id, true)
        var request = Arcbox_V1_StopContainerRequest()
        request.id = id
        do {
            _ = try await client.containers.stop(request, options: ArcBoxClient.defaultCallOptions)
            setContainerRunningState(id, isRunning: false)
        } catch {
            Log.container.error(
                "Error stopping container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "stop")
            lastError = error.localizedDescription
        }
        setTransitioning(id, false)
        await loadContainers(client: client)
    }

    /// Creates a new container via Docker API and returns its ID, or nil on failure.
    func createContainer(
        options: ContainerCreateOptions,
        docker: DockerClient?
    ) async -> String? {
        guard let docker else { return nil }
        var config = Components.Schemas.ContainerConfig()
        config.Image = options.image
        let cmdParts = options.command.split(separator: " ").map(String.init)
        if !cmdParts.isEmpty { config.Cmd = cmdParts }
        let entrypointParts = options.entrypoint.split(separator: " ").map(String.init)
        if !entrypointParts.isEmpty { config.Entrypoint = entrypointParts }
        if !options.workingDir.isEmpty { config.WorkingDir = options.workingDir }

        let policyName: Components.Schemas.RestartPolicy.NamePayload =
            switch options.restartPolicy {
            case "always": .always
            case "unless-stopped": .unless_hyphen_stopped
            case "on-failure": .on_hyphen_failure
            default: .no
            }
        var resources = Components.Schemas.Resources()
        if options.dockerInit { resources.Init = true }
        let hostConfig = Components.Schemas.HostConfig(
            value1: resources,
            value2: .init(
                RestartPolicy: .init(Name: policyName),
                AutoRemove: options.autoRemove,
                Privileged: options.privileged,
                ReadonlyRootfs: options.readOnlyRootfs
            )
        )

        do {
            let response = try await docker.api.ContainerCreate(
                query: .init(name: options.name.isEmpty ? nil : options.name, platform: options.platform),
                body: .json(.init(value1: config, value2: .init(HostConfig: hostConfig)))
            )
            switch response {
            case .created(let created):
                switch created.body {
                case .json(let body):
                    let id = body.Id
                    Log.container.info("Created container \(id, privacy: .private)")
                    await loadContainersFromDocker(docker: docker)
                    return id
                }
            case .badRequest(let err):
                Log.container.error("Bad request creating container: \(String(describing: err), privacy: .private)")
            case .notFound(let err):
                Log.container.error("Image not found: \(String(describing: err), privacy: .private)")
            case .conflict(let err):
                Log.container.error("Container name conflict: \(String(describing: err), privacy: .private)")
            case .internalServerError(let err):
                Log.container.error("Server error creating container: \(String(describing: err), privacy: .private)")
            case .undocumented(let statusCode, _):
                Log.container.error("Unexpected status \(statusCode, privacy: .public) creating container")
            }
        } catch {
            Log.container.error("Error creating container: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "create")
        }
        return nil
    }

    func removeContainer(_ id: String, client: ArcBoxClient?) async {
        lastError = nil
        guard let client else { return }
        var request = Arcbox_V1_RemoveContainerRequest()
        request.id = id
        request.force = true
        do {
            _ = try await client.containers.remove(request, options: ArcBoxClient.defaultCallOptions)
            removeContainerLocally(id)
        } catch {
            Log.container.error(
                "Error removing container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "remove")
            lastError = error.localizedDescription
        }
        await loadContainers(client: client)
    }

    func loadContainerDetails(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }

        var request = Arcbox_V1_InspectContainerRequest()
        request.id = id

        do {
            let details = try await client.containers.inspect(request, options: ArcBoxClient.defaultCallOptions)
            setContainerDetails(
                id,
                domain: Self.normalized(details.config.domainname),
                ipAddress: Self.normalized(details.networkSettings.ipAddress),
                mounts: details.mounts.map { mount in
                    ContainerMount(
                        type: mount.type,
                        source: mount.source,
                        destination: mount.destination,
                        isReadOnly: !mount.rw
                    )
                }
            )
        } catch {
            Log.container.error(
                "Error inspecting container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .container, operation: "inspect_grpc")
        }
    }

}
