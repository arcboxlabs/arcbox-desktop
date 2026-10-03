import ArcBoxClient
import Foundation
import GRPCCore
import OSLog

extension SandboxesViewModel {
    // MARK: - Port Exposure

    /// Load the daemon's authoritative host listeners for one sandbox.
    func loadExposedPorts(for sandboxID: String, client: ArcBoxClient?) async {
        guard !Task.isCancelled else { return }
        guard let client else {
            prepareExposedPortsLoad(for: sandboxID)
            exposedPortsLoadState = .waiting
            exposedPortsRefreshError = nil
            return
        }

        let metadata = SandboxMetadata.forMachine(activeMachineID)
        await loadExposedPorts(for: sandboxID) {
            var request = Arcbox_Sandbox_V1_ListExposedPortsRequest()
            request.id = sandboxID
            let response = try await client.sandboxes.listExposedPorts(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            return response.ports.map { port in
                SandboxExposedPort(
                    sandboxPort: port.sandboxPort,
                    hostPort: port.hostPort,
                    networkProtocol: port.protocol == .udp ? "udp" : "tcp"
                )
            }
        }
    }

    /// Closure-based load seam for deterministic reconciliation tests.
    func loadExposedPorts(
        for sandboxID: String,
        fetch: @MainActor () async throws -> [SandboxExposedPort]
    ) async {
        guard !Task.isCancelled else { return }
        prepareExposedPortsLoad(for: sandboxID)

        let loadToken = UUID()
        exposedPortsLoadToken = loadToken
        let isRefresh = exposedPortsLoadState.beginLoading()
        do {
            let ports = try await fetch()
            guard
                exposedPortsLoadToken == loadToken,
                exposedPortsSandboxID == sandboxID
            else { return }
            exposedPortsLoadToken = nil
            exposedPorts[sandboxID] = ports
            exposedPortsLoadState = .loaded
            exposedPortsRefreshError = nil
        } catch is CancellationError {
            guard
                exposedPortsLoadToken == loadToken,
                exposedPortsSandboxID == sandboxID
            else { return }
            exposedPortsLoadToken = nil
            exposedPortsLoadState = isRefresh ? .loaded : .waiting
        } catch {
            guard
                exposedPortsLoadToken == loadToken,
                exposedPortsSandboxID == sandboxID
            else { return }
            exposedPortsLoadToken = nil
            if exposedPortsLoadState.cancelLoading(
                for: error,
                retainingLoadedContent: isRefresh
            ) {
                return
            }
            let message = reportError(error, operation: "list_exposed_ports", surface: false)
            exposedPortsRefreshError = exposedPortsLoadState.fail(
                message,
                retainingLoadedContent: isRefresh
            )
        }
    }

    /// Expose a sandbox port on the host. Returns the mapping on success.
    ///
    /// The daemon binds the host listener on loopback. The result is reflected
    /// immediately, then reconciled against the daemon's full snapshot.
    @discardableResult
    func exposePort(
        sandboxID: String,
        sandboxPort: UInt32,
        hostPort: UInt32 = 0,
        networkProtocol: String = "tcp",
        client: ArcBoxClient?
    ) async -> SandboxExposedPort? {
        guard let client else { return nil }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_ExposePortRequest()
        request.id = sandboxID
        request.sandboxPort = sandboxPort
        request.hostPort = hostPort
        request.protocol = networkProtocol == "udp" ? .udp : .tcp
        do {
            let response = try await client.sandboxes.exposePort(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            let mapping = SandboxExposedPort(
                sandboxPort: sandboxPort,
                hostPort: response.hostPort,
                networkProtocol: networkProtocol
            )
            recordExposedPort(mapping, for: sandboxID)
            if exposedPortsSandboxID == sandboxID {
                await loadExposedPorts(for: sandboxID, client: client)
            }
            return mapping
        } catch is CancellationError {
            return nil
        } catch {
            reportError(error, operation: "expose_port")
            return nil
        }
    }

    /// Remove a previously exposed port mapping.
    func unexposePort(
        sandboxID: String,
        sandboxPort: UInt32,
        networkProtocol: String = "tcp",
        client: ArcBoxClient?
    ) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_UnexposePortRequest()
        request.id = sandboxID
        request.sandboxPort = sandboxPort
        request.protocol = networkProtocol == "udp" ? .udp : .tcp
        do {
            _ = try await client.sandboxes.unexposePort(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            removeExposedPort(
                sandboxPort: sandboxPort,
                networkProtocol: networkProtocol,
                from: sandboxID
            )
            if exposedPortsSandboxID == sandboxID {
                await loadExposedPorts(for: sandboxID, client: client)
            }
        } catch is CancellationError {
            return
        } catch {
            reportError(error, operation: "unexpose_port")
        }
    }

    func recordExposedPort(_ mapping: SandboxExposedPort, for sandboxID: String) {
        guard exposedPortsSandboxID == sandboxID else { return }
        exposedPortsLoadToken = nil
        var ports = exposedPorts[sandboxID] ?? []
        ports.removeAll { $0.id == mapping.id }
        ports.append(mapping)
        exposedPorts[sandboxID] = ports
        exposedPortsLoadState = .loaded
        exposedPortsRefreshError = nil
    }

    func removeExposedPort(
        sandboxPort: UInt32,
        networkProtocol: String,
        from sandboxID: String
    ) {
        guard exposedPortsSandboxID == sandboxID else { return }
        exposedPortsLoadToken = nil
        exposedPorts[sandboxID]?.removeAll {
            $0.sandboxPort == sandboxPort && $0.networkProtocol == networkProtocol
        }
        exposedPortsLoadState = .loaded
        exposedPortsRefreshError = nil
    }

    private func prepareExposedPortsLoad(for sandboxID: String) {
        exposedPortsLoadToken = nil
        guard exposedPortsSandboxID != sandboxID else { return }
        exposedPorts[sandboxID] = nil
        exposedPortsSandboxID = sandboxID
        exposedPortsLoadState = .waiting
        exposedPortsRefreshError = nil
    }

    // MARK: - File Transfer

    /// Read a file from the sandbox rootfs. Limited to 256 MiB server-side.
    func readFile(
        sandboxID: String,
        path: String,
        client: ArcBoxClient
    ) async throws -> Data {
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_ReadFileRequest()
        request.id = sandboxID
        request.path = path
        // No per-call timeout: transfer time scales with file size.
        return try await client.sandboxFilesystem.readFile(request, metadata: metadata) { response in
            var data = Data()
            var completed = false
            for try await chunk in response.messages {
                data.append(chunk.data)
                if chunk.done {
                    completed = true
                    break
                }
            }
            guard completed else {
                throw RPCError(
                    code: .dataLoss,
                    message: "File transfer ended before the final chunk."
                )
            }
            return data
        }
    }

    /// Write a file into the sandbox rootfs. Limited to 256 MiB server-side.
    func writeFile(
        sandboxID: String,
        path: String,
        data: Data,
        mode: UInt32 = 0,
        client: ArcBoxClient
    ) async throws {
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        let chunkSize = 512 * 1024
        _ = try await client.sandboxFilesystem.writeFile(
            metadata: metadata,
            requestProducer: { writer in
                var openMsg = Arcbox_Sandbox_V1_WriteFileRequest()
                var open = Arcbox_Sandbox_V1_WriteFileOpen()
                open.id = sandboxID
                open.path = path
                open.mode = mode
                openMsg.open = open
                try await writer.write(openMsg)

                var offset = 0
                repeat {
                    let end = min(offset + chunkSize, data.count)
                    var chunkMsg = Arcbox_Sandbox_V1_WriteFileRequest()
                    var chunk = Arcbox_Sandbox_V1_FileChunk()
                    chunk.data = data.subdata(in: offset..<end)
                    chunk.done = end == data.count
                    chunkMsg.chunk = chunk
                    try await writer.write(chunkMsg)
                    offset = end
                } while offset < data.count
            }
        )
    }
}
