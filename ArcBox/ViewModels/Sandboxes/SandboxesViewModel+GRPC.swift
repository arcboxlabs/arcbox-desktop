import ArcBoxClient
import Foundation
import GRPCCore
import OSLog

extension SandboxesViewModel {
    // MARK: - gRPC Lifecycle Operations

    /// Load sandboxes from the daemon via gRPC List.
    func loadSandboxes(client: ArcBoxClient?) async {
        guard let client else {
            Log.sandbox.debug("No ArcBox client available")
            return
        }

        await listLoadGate.run {
            await self.performLoadSandboxes(client: client)
        }
    }

    private func performLoadSandboxes(client: ArcBoxClient) async {
        let isRefresh = loadState.beginLoading()
        let transitioning = transitioningIDs
        let existingByID = Dictionary(uniqueKeysWithValues: sandboxes.map { ($0.id, $0) })
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        do {
            var summaries: [Arcbox_Sandbox_V1_SandboxSummary] = []
            var pageToken = ""
            repeat {
                var request = Arcbox_Sandbox_V1_ListSandboxesRequest()
                request.pageSize = 1_000
                request.pageToken = pageToken
                let response = try await client.sandboxes.list(
                    request,
                    metadata: metadata,
                    options: ArcBoxClient.defaultCallOptions
                )
                summaries.append(contentsOf: response.sandboxes)
                pageToken = response.nextPageToken
            } while !pageToken.isEmpty

            var viewModels = summaries.map { summary -> SandboxViewModel in
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
            loadState = .loaded
            refreshError = nil
            lastSuccessfulListLoad = ContinuousClock().now
        } catch {
            if loadState.cancelLoading(for: error, retainingLoadedContent: isRefresh) {
                return
            }
            let message = reportError(error, operation: "list", surface: false)
            refreshError = loadState.fail(
                message,
                retainingLoadedContent: isRefresh
            )
        }
    }

    /// Load full details of one sandbox via Inspect.
    func loadSandboxDetails(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_InspectSandboxRequest()
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
        } catch is CancellationError {
            return
        } catch {
            reportError(error, operation: "inspect", surface: false)
        }
    }

    /// Create a sandbox. Returns the new sandbox ID on success.
    @discardableResult
    func createSandbox(
        _ spec: SandboxCreateSpec,
        client: ArcBoxClient?
    ) async -> String? {
        lastError = nil
        guard let client else {
            lastError = "ArcBox daemon is unavailable."
            return nil
        }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_CreateSandboxRequest()
        request.id = UUID().uuidString
        request.labels = spec.labels
        if spec.vcpus > 0 || spec.memoryMiB > 0 {
            request.limits.vcpus = spec.vcpus
            request.limits.memoryMib = spec.memoryMiB
        }
        request.cmd = spec.cmd
        request.env = spec.env
        request.workingDir = spec.workingDir
        request.user = spec.user
        if spec.networkMode != .unspecified {
            request.network.mode = spec.networkMode
        }
        request.ttlSeconds = spec.ttlSeconds
        request.template = spec.template

        for attempt in 0..<3 {
            do {
                let response = try await client.sandboxes.create(
                    request,
                    metadata: metadata,
                    options: ArcBoxClient.sandboxCreateCallOptions
                )
                Log.sandbox.info("Created sandbox \(response.id, privacy: .public)")
                return response.id
            } catch is CancellationError {
                return nil
            } catch {
                if attempt > 0,
                    let rpcError = error as? RPCError,
                    rpcError.code == .alreadyExists
                {
                    Log.sandbox.warning(
                        "Sandbox create outcome is uncertain for ID \(request.id, privacy: .public)"
                    )
                    lastError =
                        "Sandbox creation may still be completing. Close this sheet and check the list before retrying."
                    return nil
                }

                guard attempt < 2, Self.isRetryableTransportError(error) else {
                    reportError(error, operation: "create")
                    return nil
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return nil
                }
            }
        }
        return nil
    }

    /// Stop a sandbox gracefully. The event monitor delivers the final state.
    func stopSandbox(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        setTransitioning(id, true)
        // Reflect the in-flight drain immediately. Stop returns only once the
        // workload has drained and the VM is down, so the terminal .stopped
        // state arrives via the event stream — setting .stopping after the
        // await would clobber it and could wedge the row at "Stopping".
        updateSandbox(id) { $0.state = .stopping }
        var request = Arcbox_Sandbox_V1_StopSandboxRequest()
        request.id = id
        do {
            // No per-call timeout: Stop drains the active workload server-side.
            _ = try await client.sandboxes.stop(request, metadata: metadata)
        } catch is CancellationError {
            // The view initiating the operation went away.
        } catch {
            reportError(error, operation: "stop")
            // Stop failed — the optimistic .stopping is stale; resync from the daemon.
            await loadSandboxes(client: client)
        }
        setTransitioning(id, false)
    }

    /// Forcibly remove a sandbox and all its resources.
    func removeSandbox(_ id: String, force: Bool = false, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        setTransitioning(id, true)
        var request = Arcbox_Sandbox_V1_RemoveSandboxRequest()
        request.id = id
        request.force = force
        do {
            _ = try await client.sandboxes.remove(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            removeSandboxLocally(id)
        } catch is CancellationError {
            setTransitioning(id, false)
        } catch {
            reportError(error, operation: "remove")
            setTransitioning(id, false)
        }
    }
}

extension SandboxesViewModel {
    fileprivate static func isRetryableTransportError(_ error: Error) -> Bool {
        guard let rpcError = error as? RPCError else { return true }
        switch rpcError.code {
        case .cancelled, .deadlineExceeded, .unavailable:
            return true
        default:
            return false
        }
    }
}
