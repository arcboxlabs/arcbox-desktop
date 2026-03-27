import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

/// gRPC client for communicating with the arcbox daemon via Unix socket.
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

    private let grpcClient: GRPCClient<HTTP2ClientTransport.TransportServices>

    /// Creates a new client targeting the given Unix socket path.
    ///
    /// The client transport is not started until ``runConnections()`` is called.
    public init(socketPath: String = ArcBoxClient.defaultSocketPath) throws {
        let transport = try HTTP2ClientTransport.TransportServices(
            target: .unixDomainSocket(path: socketPath),
            transportSecurity: .plaintext,
            config: .defaults { $0.http2.authority = "arcbox.local" }
        )
        self.grpcClient = GRPCClient(transport: transport)
    }

    /// Run the client transport. Blocks until the client is shut down.
    ///
    /// Call this in a background `Task` before making any RPC calls.
    public func runConnections() async throws {
        try await grpcClient.runConnections()
    }

    /// Initiate graceful shutdown of the client transport.
    public func close() {
        grpcClient.beginGracefulShutdown()
    }

    // MARK: - Service Accessors

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
}
