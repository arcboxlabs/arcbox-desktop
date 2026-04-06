import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices
import os

/// gRPC client for communicating with the arcbox daemon via Unix socket.
///
/// The client automatically recovers from transport failures (daemon restart,
/// socket deletion) by recreating the underlying `GRPCClient` when
/// `runConnections()` returns.  Service accessors (`.system`, `.containers`,
/// etc.) always reflect the latest transport — callers must NOT cache the
/// returned service clients across await boundaries.
///
/// Usage:
/// ```swift
/// let client = try ArcBoxClient()
/// Task { try await client.runConnections() }
/// let response = try await client.containers.list(.init())
/// client.close()
/// ```
@available(macOS 15.0, *)
public final class ArcBoxClient: Sendable {
    /// Default Unix socket path for the arcbox daemon.
    public static let defaultSocketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.arcbox/run/arcbox.sock"
    }()

    private let socketPath: String
    private let _grpcClient: OSAllocatedUnfairLock<GRPCClient<HTTP2ClientTransport.TransportServices>>
    private let _closed: OSAllocatedUnfairLock<Bool>

    /// Creates a new client targeting the given Unix socket path.
    ///
    /// The client transport is not started until ``runConnections()`` is called.
    public init(socketPath: String = ArcBoxClient.defaultSocketPath) throws {
        self.socketPath = socketPath
        self._closed = OSAllocatedUnfairLock(initialState: false)
        let transport = try HTTP2ClientTransport.TransportServices(
            target: .unixDomainSocket(path: socketPath),
            transportSecurity: .plaintext,
            config: .defaults { $0.http2.authority = "arcbox.local" }
        )
        self._grpcClient = OSAllocatedUnfairLock(
            initialState: GRPCClient(transport: transport))
    }

    /// Run the client transport with automatic recovery.
    ///
    /// `GRPCClient.runConnections()` is one-shot — once it returns, the client
    /// is permanently dead ("After this method returns, the client is no longer
    /// usable").  This wrapper detects termination and recreates the transport
    /// so the `ArcBoxClient` instance remains usable across daemon restarts.
    ///
    /// Blocks until the task is cancelled or ``close()`` is called.
    public func runConnections() async throws {
        while !Task.isCancelled && !_closed.withLock({ $0 }) {
            let client = _grpcClient.withLock { $0 }
            do {
                try await client.runConnections()
            } catch is CancellationError {
                return
            } catch {
                ClientLog.grpc.warning("gRPC transport failed, will recreate: \(error)")
            }

            guard !Task.isCancelled, !_closed.withLock({ $0 }) else { return }

            // Recreate transport so subsequent RPCs use a fresh connection.
            do {
                let transport = try HTTP2ClientTransport.TransportServices(
                    target: .unixDomainSocket(path: socketPath),
                    transportSecurity: .plaintext,
                    config: .defaults { $0.http2.authority = "arcbox.local" }
                )
                _grpcClient.withLock { $0 = GRPCClient(transport: transport) }
            } catch {
                // Transport creation shouldn't fail for Unix domain sockets.
                try? await Task.sleep(for: .seconds(5))
                continue
            }

            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Whether the client has been closed.
    public var isClosed: Bool {
        _closed.withLock { $0 }
    }

    /// Initiate graceful shutdown of the client transport.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops.
    public func close() {
        let wasClosed = _closed.withLock { val -> Bool in
            let prev = val
            val = true
            return prev
        }
        guard !wasClosed else { return }
        _grpcClient.withLock { $0 }.beginGracefulShutdown()
        ClientLog.grpc.info("ArcBoxClient closed")
    }

    // MARK: - Service Accessors

    /// Default RPC timeout for unary calls (prevents UI freeze if daemon hangs).
    public static let defaultRPCTimeout: Duration = .seconds(15)

    /// Current gRPC client — may change after transport recovery.
    private var grpcClient: GRPCClient<HTTP2ClientTransport.TransportServices> {
        _grpcClient.withLock { $0 }
    }

    /// Default call options with timeout.
    public static var defaultCallOptions: GRPCCore.CallOptions {
        var options = CallOptions.defaults
        options.timeout = defaultRPCTimeout
        return options
    }

    /// Container lifecycle operations.
    public var containers: Arcbox_V1_ContainerService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Image management operations.
    public var images: Arcbox_V1_ImageService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Network management operations.
    public var networks: Arcbox_V1_NetworkService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// System-level operations (info, version, ping, events, prune).
    public var system: Arcbox_V1_SystemService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Volume management operations.
    public var volumes: Arcbox_V1_VolumeService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Virtual machine management operations.
    public var machines: Arcbox_V1_MachineService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Container image icon lookups.
    public var icons: Arcbox_V1_IconService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Sandbox lifecycle operations.
    public var sandboxes: Sandbox_V1_SandboxService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Sandbox snapshot operations.
    public var snapshots: Sandbox_V1_SandboxSnapshotService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    /// Kubernetes cluster lifecycle operations.
    public var kubernetes: Arcbox_V1_KubernetesService.Client<HTTP2ClientTransport.TransportServices> {
        .init(wrapping: grpcClient)
    }

    // MARK: - Error Mapping

    /// Map a gRPC or transport error to a user-friendly message.
    public static func userMessage(for error: Error) -> String {
        let desc = String(describing: error)

        if desc.contains("unavailable") || desc.contains("UNAVAILABLE") {
            return "Cannot reach ArcBox daemon. Is it running?"
        }
        if desc.contains("deadline") || desc.contains("DEADLINE_EXCEEDED") {
            return "Operation timed out. The daemon may be busy."
        }
        if desc.contains("not found") || desc.contains("NOT_FOUND") {
            return "Resource not found. It may have been removed."
        }
        if desc.contains("already exists") || desc.contains("ALREADY_EXISTS") {
            return "A resource with that name already exists."
        }
        if desc.contains("permission") || desc.contains("PERMISSION_DENIED") {
            return "Permission denied. Check daemon privileges."
        }
        if desc.contains("ECONNREFUSED") || desc.contains("Connection refused") {
            return "Connection refused. Is the ArcBox daemon running?"
        }

        return error.localizedDescription
    }
}
