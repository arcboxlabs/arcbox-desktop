import Foundation
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import HTTPTypes

/// A custom transport that routes OpenAPI requests through a Unix domain socket
/// using AsyncHTTPClient's `http+unix://` URL scheme.
struct UnixSocketTransport: ClientTransport {
    private let client: HTTPClient
    private let socketPath: String
    private let timeout: TimeAmount

    init(client: HTTPClient, socketPath: String, timeout: TimeAmount = .minutes(1)) {
        self.client = client
        self.socketPath = socketPath
        self.timeout = timeout
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // Build the path from baseURL + request path
        let basePath = baseURL.path  // e.g. "/v1.47"
        let requestPath = request.path ?? ""
        let fullPath = basePath + requestPath

        // Encode socket path for http+unix:// URL scheme
        let encodedSocket = socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let urlString = "http+unix://\(encodedSocket)\(fullPath)"

        var clientRequest = HTTPClientRequest(url: urlString)
        clientRequest.method = httpMethod(from: request.method)
        for header in request.headerFields {
            clientRequest.headers.add(name: header.name.canonicalName, value: header.value)
        }

        if let body {
            let length: HTTPClientRequest.Body.Length
            switch body.length {
            case .unknown: length = .unknown
            case .known(let count): length = .known(count)
            }
            clientRequest.body = .stream(body.map { .init(bytes: $0) }, length: length)
        }

        let httpResponse = try await client.execute(clientRequest, timeout: timeout)

        var headerFields: HTTPFields = [:]
        for header in httpResponse.headers {
            if let name = HTTPField.Name(header.name) {
                headerFields[name] = header.value
            }
        }

        let responseBody: HTTPBody?
        switch request.method {
        case .head, .connect, .trace:
            responseBody = nil
        default:
            let contentLength: HTTPBody.Length
            if let lengthStr = headerFields[.contentLength], let len = Int64(lengthStr) {
                contentLength = .known(len)
            } else {
                contentLength = .unknown
            }
            responseBody = HTTPBody(
                httpResponse.body.map { $0.readableBytesView },
                length: contentLength,
                iterationBehavior: .single
            )
        }

        let response = HTTPResponse(
            status: .init(code: Int(httpResponse.status.code)),
            headerFields: headerFields
        )
        return (response, responseBody)
    }

    private func httpMethod(from method: HTTPRequest.Method) -> NIOHTTP1.HTTPMethod {
        switch method {
        case .get: return .GET
        case .put: return .PUT
        case .post: return .POST
        case .delete: return .DELETE
        case .options: return .OPTIONS
        case .head: return .HEAD
        case .patch: return .PATCH
        case .trace: return .TRACE
        default: return .RAW(value: method.rawValue)
        }
    }
}

/// HTTP client for communicating with the Docker Engine API via Unix socket.
///
/// Usage:
/// ```swift
/// let client = DockerClient()
/// let response = try await client.api.ContainerList()
/// ```
@available(macOS 15.0, *)
public struct DockerClient: Sendable {
    /// Default Unix socket path for the Docker daemon.
    public static let defaultSocketPath = "/var/run/docker.sock"

    /// Default server URL matching the OpenAPI spec base path.
    public static let defaultServerURL = try! Servers.Server1.url()

    /// The generated OpenAPI client — use this to call Docker API operations.
    public let api: Client

    /// The underlying AsyncHTTPClient instance (for lifecycle management).
    private let httpClient: HTTPClient

    /// Creates a new Docker client targeting the given Unix socket path.
    ///
    /// - Parameter socketPath: Path to the Docker daemon Unix socket.
    public init(socketPath: String = DockerClient.defaultSocketPath) {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let transport = UnixSocketTransport(client: httpClient, socketPath: socketPath)
        self.httpClient = httpClient
        self.api = Client(
            serverURL: Self.defaultServerURL,
            transport: transport
        )
    }

    /// Gracefully shut down the underlying HTTP client.
    public func shutdown() async throws {
        try await httpClient.shutdown()
    }
}
