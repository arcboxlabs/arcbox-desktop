import ArcBoxClient
import Foundation
import GRPCCore
import OSLog

extension SandboxesViewModel {
    // MARK: - Port Exposure

    /// Expose a sandbox port on the host. Returns the mapping on success.
    ///
    /// The daemon binds the host listener on loopback; sandbox.v1 has no RPC
    /// to enumerate mappings, so the result is also recorded in
    /// `exposedPorts` for session-local display.
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
        var request = Sandbox_V1_ExposePortRequest()
        request.id = sandboxID
        request.sandboxPort = sandboxPort
        request.hostPort = hostPort
        request.protocol = networkProtocol
        do {
            let response = try await client.sandboxes.exposePort(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            let mapping = SandboxExposedPort(
                sandboxPort: sandboxPort,
                hostPort: response.hostPort,
                guestPort: response.guestPort,
                networkProtocol: networkProtocol
            )
            var ports = exposedPorts[sandboxID] ?? []
            ports.removeAll { $0.id == mapping.id }
            ports.append(mapping)
            exposedPorts[sandboxID] = ports
            return mapping
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
        var request = Sandbox_V1_UnexposePortRequest()
        request.id = sandboxID
        request.sandboxPort = sandboxPort
        request.protocol = networkProtocol
        do {
            _ = try await client.sandboxes.unexposePort(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            exposedPorts[sandboxID]?.removeAll {
                $0.sandboxPort == sandboxPort && $0.networkProtocol == networkProtocol
            }
        } catch {
            reportError(error, operation: "unexpose_port")
        }
    }

    // MARK: - File Transfer

    /// Read a file from the sandbox rootfs. Limited to 256 MiB server-side.
    func readFile(
        sandboxID: String,
        path: String,
        client: ArcBoxClient
    ) async throws -> Data {
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_ReadFileRequest()
        request.id = sandboxID
        request.path = path
        // No per-call timeout: transfer time scales with file size.
        return try await client.sandboxes.readFile(request, metadata: metadata) { response in
            var data = Data()
            for try await chunk in response.messages {
                data.append(chunk.data)
                if chunk.done { break }
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
        _ = try await client.sandboxes.writeFile(
            metadata: metadata,
            requestProducer: { writer in
                var openMsg = Sandbox_V1_WriteFileRequest()
                var open = Sandbox_V1_WriteFileOpen()
                open.id = sandboxID
                open.path = path
                open.mode = mode
                openMsg.open = open
                try await writer.write(openMsg)

                var offset = 0
                repeat {
                    let end = min(offset + chunkSize, data.count)
                    var chunkMsg = Sandbox_V1_WriteFileRequest()
                    var chunk = Sandbox_V1_FileChunk()
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
