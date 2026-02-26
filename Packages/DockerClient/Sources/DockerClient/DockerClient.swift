import Foundation
import OpenAPIRuntime
import OpenAPIAsyncHTTPClient
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import HTTPTypes

@available(macOS 15.0, *)
public struct ContainerInspectMountSnapshot: Sendable {
    public let type: String?
    public let source: String?
    public let destination: String?
    public let rw: Bool?

    public init(type: String?, source: String?, destination: String?, rw: Bool?) {
        self.type = type
        self.source = source
        self.destination = destination
        self.rw = rw
    }
}

@available(macOS 15.0, *)
public struct ContainerInspectSnapshot: Sendable {
    public let domainname: String?
    public let ipAddress: String?
    public let mounts: [ContainerInspectMountSnapshot]

    public init(domainname: String?, ipAddress: String?, mounts: [ContainerInspectMountSnapshot]) {
        self.domainname = domainname
        self.ipAddress = ipAddress
        self.mounts = mounts
    }
}

@available(macOS 15.0, *)
public enum DockerClientError: Error, Sendable {
    case invalidHTTPStatus(Int)
    case invalidResponseBody
    case invalidJSON
}

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
    private let socketPath: String
    private let timeout: TimeAmount

    /// Creates a new Docker client targeting the given Unix socket path.
    ///
    /// - Parameter socketPath: Path to the Docker daemon Unix socket.
    public init(socketPath: String = DockerClient.defaultSocketPath) {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        let transport = UnixSocketTransport(client: httpClient, socketPath: socketPath)
        self.httpClient = httpClient
        self.socketPath = socketPath
        self.timeout = .minutes(1)
        self.api = Client(
            serverURL: Self.defaultServerURL,
            transport: transport
        )
    }

    /// Raw inspect fallback that bypasses generated date decoding.
    ///
    /// Docker sometimes returns date fields that fail strict OpenAPI decoding.
    /// This method parses only the fields we need from raw JSON.
    public func inspectContainerSnapshot(id: String) async throws -> ContainerInspectSnapshot {
        let encodedSocket = socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let path = Self.defaultServerURL.path + "/containers/\(encodedID)/json"
        let urlString = "http+unix://\(encodedSocket)\(path)"

        var request = HTTPClientRequest(url: urlString)
        request.method = .GET
        request.headers.add(name: "Accept", value: "application/json")

        let response = try await httpClient.execute(request, timeout: timeout)
        guard (200..<300).contains(response.status.code) else {
            throw DockerClientError.invalidHTTPStatus(Int(response.status.code))
        }

        var data = Data()
        for try await var chunk in response.body {
            if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                data.append(contentsOf: bytes)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DockerClientError.invalidJSON
        }

        let config = json["Config"] as? [String: Any]
        let domainname = Self.normalized(config?["Domainname"] as? String)

        let networkSettings = json["NetworkSettings"] as? [String: Any]
        let primaryIP = Self.normalized(networkSettings?["IPAddress"] as? String)
        var ipAddress = primaryIP
        if ipAddress == nil,
            let networks = networkSettings?["Networks"] as? [String: Any]
        {
            for value in networks.values {
                guard let endpoint = value as? [String: Any] else { continue }
                if let ip = Self.normalized(endpoint["IPAddress"] as? String) {
                    ipAddress = ip
                    break
                }
            }
        }

        let mountsArray = json["Mounts"] as? [[String: Any]] ?? []
        let mounts = mountsArray.map { mount in
            ContainerInspectMountSnapshot(
                type: Self.normalized(mount["Type"] as? String),
                source: Self.normalized(mount["Source"] as? String),
                destination: Self.normalized(mount["Destination"] as? String),
                rw: mount["RW"] as? Bool
            )
        }

        return ContainerInspectSnapshot(
            domainname: domainname,
            ipAddress: ipAddress,
            mounts: mounts
        )
    }

    /// Gracefully shut down the underlying HTTP client.
    public func shutdown() async throws {
        try await httpClient.shutdown()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
