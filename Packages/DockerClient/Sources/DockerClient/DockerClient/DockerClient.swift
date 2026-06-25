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
        return "\(home)/.arcbox/run/docker.sock"
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

    /// The underlying AsyncHTTPClient instance (for lifecycle management).
    let httpClient: HTTPClient
    let socketPath: String
    let timeout: TimeAmount

    /// Creates a new Docker client targeting the given Unix socket path.
    ///
    /// - Parameter socketPath: Path to the Docker daemon Unix socket.
    public init(socketPath: String = DockerClient.defaultSocketPath) {
        // Use POSIX sockets (MultiThreadedEventLoopGroup) instead of the default
        // NIOTransportServices (Network.framework) which has issues with Unix
        // domain sockets on macOS, causing ENETDOWN errors.
        let httpClient = HTTPClient(
            eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton))
        let transport = UnixSocketTransport(client: httpClient, socketPath: socketPath)
        self.httpClient = httpClient
        self.socketPath = socketPath
        self.timeout = .minutes(1)
        self.api = Client(
            serverURL: Self.defaultServerURL,
            transport: transport
        )
    }
}
