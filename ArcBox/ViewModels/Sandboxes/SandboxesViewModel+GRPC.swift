import ArcBoxClient
import DockerClient
import Foundation
import OSLog

extension SandboxesViewModel {
    // MARK: - gRPC Lifecycle Operations

    /// Load sandboxes from the daemon via gRPC List.
    func loadSandboxes(client: ArcBoxClient?) async {
        guard let client else { return }
        let transitioning = transitioningIDs
        let existingByID = Dictionary(uniqueKeysWithValues: sandboxes.map { ($0.id, $0) })
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        do {
            let response = try await client.sandboxes.list(
                Sandbox_V1_ListSandboxesRequest(),
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            var viewModels = response.sandboxes.map { summary -> SandboxViewModel in
                var vm = SandboxViewModel(from: summary)
                // Preserve detail fields loaded by a prior Inspect so the list
                // refresh does not wipe data the summary endpoint doesn't return.
                if let existing = existingByID[vm.id] {
                    vm.preserveDetailFrom(existing)
                }
                return vm
            }
            for i in viewModels.indices where transitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            sandboxes = viewModels
            lastError = nil
            updateMonitoringMetrics()
        } catch {
            reportError(error, operation: "list")
        }
    }

    /// Load full details of one sandbox via Inspect.
    func loadSandboxDetails(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_InspectSandboxRequest()
        request.id = id
        do {
            let info = try await client.sandboxes.inspect(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            updateSandbox(id) { sandbox in
                sandbox.applyDetails(from: info)
            }
        } catch {
            reportError(error, operation: "inspect", surface: false)
        }
    }

    /// Create a sandbox. Returns the new sandbox ID on success.
    @discardableResult
    func createSandbox(
        _ spec: SandboxCreateSpec,
        client: ArcBoxClient?,
        docker: DockerClient? = nil
    ) async -> String? {
        guard let client else { return nil }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_CreateSandboxRequest()
        request.labels = spec.labels
        request.kernel = spec.kernel
        request.bootArgs = spec.bootArgs
        if spec.vcpus > 0 || spec.memoryMiB > 0 {
            request.limits.vcpus = spec.vcpus
            request.limits.memoryMib = spec.memoryMiB
        }
        request.cmd = spec.cmd
        request.env = spec.env
        request.workingDir = spec.workingDir
        request.user = spec.user
        if !spec.networkMode.isEmpty {
            request.network.mode = spec.networkMode
        }
        request.ttlSeconds = spec.ttlSeconds

        // Resolve a Docker image to its overlay2 layer directory. The path is
        // guest-visible (Docker runs inside the machine), and the guest agent
        // builds the sandbox rootfs from it (same as CLI --from-image).
        if !spec.image.isEmpty, let docker {
            do {
                let snapshot = try await docker.inspectImageSnapshot(id: spec.image)
                guard let layerDir = snapshot.overlayChainDirectory else {
                    lastError = "Image \(spec.image) has no overlay2 layer directory"
                    return nil
                }
                request.rootfs = layerDir
                Log.sandbox.info(
                    "Resolved image \(spec.image, privacy: .public) to layer \(layerDir, privacy: .public)"
                )
            } catch {
                reportError(error, operation: "resolve_image")
                return nil
            }
        } else if !spec.rootfs.isEmpty {
            request.rootfs = spec.rootfs
        }

        do {
            let response = try await client.sandboxes.create(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            Log.sandbox.info("Created sandbox \(response.id, privacy: .public)")
            recordSandboxStart()
            await loadSandboxes(client: client)
            return response.id
        } catch {
            reportError(error, operation: "create")
            return nil
        }
    }

    /// Stop a sandbox gracefully. The event monitor delivers the final state.
    func stopSandbox(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        setTransitioning(id, true)
        var request = Sandbox_V1_StopSandboxRequest()
        request.id = id
        do {
            // No per-call timeout: Stop drains the active workload server-side.
            _ = try await client.sandboxes.stop(request, metadata: metadata)
            updateSandbox(id) { $0.state = .stopping }
        } catch {
            reportError(error, operation: "stop")
        }
        setTransitioning(id, false)
    }

    /// Forcibly remove a sandbox and all its resources.
    func removeSandbox(_ id: String, force: Bool = false, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        setTransitioning(id, true)
        var request = Sandbox_V1_RemoveSandboxRequest()
        request.id = id
        request.force = force
        do {
            _ = try await client.sandboxes.remove(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            removeSandboxLocally(id)
        } catch {
            reportError(error, operation: "remove")
            setTransitioning(id, false)
        }
    }
}
