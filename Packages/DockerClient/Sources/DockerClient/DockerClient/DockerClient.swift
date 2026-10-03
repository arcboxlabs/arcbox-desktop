import AsyncHTTPClient
import Foundation
import NIOCore
import NIOPosix

/// HTTP client for communicating with the Docker Engine API via Unix socket.
///
/// Usage:
/// ```swift
/// let client = DockerClient()
/// let response = try await client.api.ContainerList()
/// ```
@available(macOS 15.0, *)
public struct DockerClient: Sendable {
    /// Default Unix socket path for the Docker daemon (ArcBox runtime).
    public static let defaultSocketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDir = profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        return "\(home)/\(dataDir)/run/docker.sock"
    }()

    /// Default server URL matching the OpenAPI spec base path.
    public static let defaultServerURL: URL = {
        guard let url = try? Servers.Server1.url() else {
            fatalError("DockerClient: Failed to construct default server URL from OpenAPI spec")
        }
        return url
    }()

    /// The generated OpenAPI client — use this to call Docker API operations.
    public let api: Client

    /// Carries every request that answers and ends.
    let httpClient: HTTPClient
    /// Carries the follows — `/events` and `logs?follow=true` — which hold their connection
    /// for as long as the view that opened them. Sharing one pool with the requests meant
    /// every open stream permanently cost the request path a connection out of eight, and a
    /// batch operation queued behind the rest failed with `getConnectionFromPoolTimeout`.
    let streamingClient: HTTPClient
    let socketPath: String
    let timeout: TimeAmount

    /// Creates a new Docker client targeting the given Unix socket path.
    ///
    /// - Parameter socketPath: Path to the Docker daemon Unix socket.
    public init(socketPath: String = DockerClient.defaultSocketPath) {
        self.httpClient = Self.makeHTTPClient(connections: 16)
        // One `/events` follow, plus one per open logs tab.
        self.streamingClient = Self.makeHTTPClient(connections: 8)
        self.socketPath = socketPath
        self.timeout = .minutes(1)
        self.api = Client(
            serverURL: Self.defaultServerURL,
            transport: UnixSocketTransport(client: httpClient, socketPath: socketPath)
        )
    }

    private static func makeHTTPClient(connections: Int) -> HTTPClient {
        var configuration = HTTPClient.Configuration()
        // AsyncHTTPClient's default of 8 is sized for connections to a remote host over the
        // network. This one is a Unix socket to a daemon on the same machine, where a
        // connection is cheap and the cost of running out is a visible failure.
        configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit = connections
        // Use POSIX sockets (MultiThreadedEventLoopGroup) instead of the default
        // NIOTransportServices (Network.framework) which has issues with Unix
        // domain sockets on macOS, causing ENETDOWN errors.
        return HTTPClient(
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
            configuration: configuration
        )
    }
}
