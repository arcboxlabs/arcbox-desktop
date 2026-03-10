import AsyncHTTPClient
import Foundation
import HTTPTypes
import NIOCore
import NIOHTTP1
import NIOPosix
import OpenAPIAsyncHTTPClient
import OpenAPIRuntime

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
    public let rootfsMountPath: String?

    public init(
        domainname: String?,
        ipAddress: String?,
        mounts: [ContainerInspectMountSnapshot],
        rootfsMountPath: String? = nil
    ) {
        self.domainname = domainname
        self.ipAddress = ipAddress
        self.mounts = mounts
        self.rootfsMountPath = rootfsMountPath
    }
}

@available(macOS 15.0, *)
public struct ImageInspectSnapshot: Sendable {
    public let labels: [String: String]
    public let rootfsMountPath: String?

    public init(labels: [String: String], rootfsMountPath: String? = nil) {
        self.labels = labels
        self.rootfsMountPath = rootfsMountPath
    }
}

@available(macOS 15.0, *)
public enum DockerClientError: Error, Sendable {
    case invalidHTTPStatus(Int)
    case invalidResponseBody
    case invalidJSON
}

/// A single line from Docker container logs.
@available(macOS 15.0, *)
public struct DockerLogLine: Sendable {
    public enum Stream: Sendable {
        case stdout
        case stderr
    }

    public let stream: Stream
    public let message: String
    public let timestamp: String?

    public init(stream: Stream, message: String, timestamp: String? = nil) {
        self.stream = stream
        self.message = message
        self.timestamp = timestamp
    }
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
        let encodedSocket =
            socketPath
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
            // Eagerly collect the full body while the connection is still alive.
            // Docker often sends `connection: close` with chunked encoding,
            // which can drop the socket before a lazy consumer reads the data.
            var collected = Data()
            for try await var chunk in httpResponse.body {
                if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                    collected.append(contentsOf: bytes)
                }
            }
            responseBody = HTTPBody(collected)
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
    /// Default Unix socket path for the Docker daemon (ArcBox runtime).
    public static let defaultSocketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.arcbox/run/docker.sock"
    }()

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

    /// Raw inspect fallback that bypasses generated date decoding.
    ///
    /// Docker sometimes returns date fields that fail strict OpenAPI decoding.
    /// This method parses only the fields we need from raw JSON.
    public func inspectContainerSnapshot(id: String) async throws -> ContainerInspectSnapshot {
        let encodedSocket =
            socketPath
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

        let graphDriver = json["GraphDriver"] as? [String: Any]
        let graphDriverData = graphDriver?["Data"] as? [String: Any]
        let rootfsMountPath =
            Self.normalized(graphDriverData?["MergedDir"] as? String)
            ?? Self.normalized(graphDriverData?["UpperDir"] as? String)

        return ContainerInspectSnapshot(
            domainname: domainname,
            ipAddress: ipAddress,
            mounts: mounts,
            rootfsMountPath: rootfsMountPath
        )
    }

    /// Raw image inspect fallback that bypasses generated date decoding.
    /// Parses only fields used by UI.
    public func inspectImageSnapshot(id: String) async throws -> ImageInspectSnapshot {
        let encodedSocket =
            socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let path = Self.defaultServerURL.path + "/images/\(encodedID)/json"
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
        let containerConfig = json["ContainerConfig"] as? [String: Any]
        let labels =
            Self.extractStringMap(config?["Labels"])
            ?? Self.extractStringMap(containerConfig?["Labels"])
            ?? [:]

        let graphDriver = json["GraphDriver"] as? [String: Any]
        let graphDriverData = graphDriver?["Data"] as? [String: Any]
        let rootfsMountPath =
            Self.normalized(graphDriverData?["MergedDir"] as? String)
            ?? Self.normalized(graphDriverData?["UpperDir"] as? String)
            ?? Self.normalized(graphDriverData?["Dir"] as? String)

        return ImageInspectSnapshot(
            labels: labels,
            rootfsMountPath: rootfsMountPath
        )
    }

    // MARK: - Docker Events

    /// A single event from the Docker daemon `/events` stream.
    public struct DockerEvent: Sendable {
        public let type: String  // "container", "image", "network", "volume", …
        public let action: String  // "start", "stop", "die", "create", "destroy", …
        public let actorID: String?
    }

    /// Stream real-time events from the Docker daemon.
    /// Cancel the returned Task to stop listening.
    public func streamEvents() -> AsyncThrowingStream<DockerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let encodedSocket =
                        socketPath
                        .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
                    let path = Self.defaultServerURL.path + "/events"
                    let urlString = "http+unix://\(encodedSocket)\(path)"

                    var request = HTTPClientRequest(url: urlString)
                    request.method = .GET
                    request.headers.add(name: "Accept", value: "application/json")

                    let response = try await httpClient.execute(request, timeout: .hours(24))

                    var buffer = Data()
                    for try await var chunk in response.body {
                        if Task.isCancelled { break }
                        if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                            buffer.append(contentsOf: bytes)
                        }

                        // Each event is a JSON object terminated by newline
                        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                            let lineData = buffer[buffer.startIndex..<newlineIndex]
                            buffer.removeFirst(newlineIndex - buffer.startIndex + 1)

                            guard !lineData.isEmpty,
                                let json = try? JSONSerialization.jsonObject(with: lineData)
                                    as? [String: Any],
                                let type = json["Type"] as? String,
                                let action = json["Action"] as? String
                            else { continue }

                            let actor = json["Actor"] as? [String: Any]
                            let actorID = actor?["ID"] as? String

                            continuation.yield(
                                DockerEvent(type: type, action: action, actorID: actorID))
                        }
                    }
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Container Logs

    /// Fetch container logs as a batch (non-streaming).
    public func fetchContainerLogs(
        id: String,
        tail: Int = 500,
        timestamps: Bool = true
    ) async throws -> [DockerLogLine] {
        let data = try await rawContainerLogsRequest(
            id: id, follow: false, tail: tail, timestamps: timestamps
        )
        return Self.parseMultiplexedStream(data, timestamps: timestamps)
    }

    /// Stream container logs in real-time. Cancel the Task to stop streaming.
    /// Auto-detects multiplexed vs raw TTY format from the first chunk.
    public func streamContainerLogs(
        id: String,
        tail: Int = 500,
        timestamps: Bool = true,
        since: Int = 0
    ) -> AsyncThrowingStream<DockerLogLine, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await rawContainerLogsHTTPResponse(
                        id: id, follow: true, tail: tail, timestamps: timestamps, since: since
                    )

                    var buffer = Data()
                    var isMultiplexed: Bool?

                    for try await var chunk in response.body {
                        if Task.isCancelled { break }
                        if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                            buffer.append(contentsOf: bytes)
                        }

                        // Detect format from first chunk
                        if isMultiplexed == nil && !buffer.isEmpty {
                            isMultiplexed = Self.isMultiplexedStream(buffer)
                        }

                        if isMultiplexed == true {
                            // Parse complete multiplexed frames from buffer
                            while buffer.count >= 8 {
                                let streamByte = buffer[buffer.startIndex]
                                let sizeBytes = buffer[
                                    buffer.startIndex + 4..<buffer.startIndex + 8]
                                let payloadSize = Int(
                                    UInt32(sizeBytes[sizeBytes.startIndex]) << 24
                                        | UInt32(sizeBytes[sizeBytes.startIndex + 1]) << 16
                                        | UInt32(sizeBytes[sizeBytes.startIndex + 2]) << 8
                                        | UInt32(sizeBytes[sizeBytes.startIndex + 3])
                                )

                                guard buffer.count >= 8 + payloadSize else { break }

                                let payload = buffer[
                                    buffer.startIndex + 8..<buffer.startIndex + 8 + payloadSize]
                                buffer.removeFirst(8 + payloadSize)

                                let stream: DockerLogLine.Stream =
                                    streamByte == 2 ? .stderr : .stdout

                                guard let text = String(data: payload, encoding: .utf8) else {
                                    continue
                                }
                                let lines = text.split(
                                    separator: "\n", omittingEmptySubsequences: false)
                                for line in lines {
                                    let lineStr = String(line)
                                    if lineStr.isEmpty { continue }
                                    let (ts, msg) =
                                        timestamps
                                        ? Self.splitTimestamp(lineStr)
                                        : (nil, lineStr)
                                    continuation.yield(
                                        DockerLogLine(stream: stream, message: msg, timestamp: ts))
                                }
                            }
                        } else {
                            // Raw TTY: parse complete lines from buffer
                            guard let text = String(data: buffer, encoding: .utf8) else { continue }
                            // Keep incomplete last line in buffer
                            if let lastNewline = text.lastIndex(of: "\n") {
                                let completeText = String(text[text.startIndex...lastNewline])
                                let remaining = String(text[text.index(after: lastNewline)...])
                                buffer = remaining.data(using: .utf8) ?? Data()

                                for line in completeText.split(
                                    separator: "\n", omittingEmptySubsequences: false)
                                {
                                    let lineStr = String(line)
                                    if lineStr.isEmpty { continue }
                                    let (ts, msg) =
                                        timestamps
                                        ? Self.splitTimestamp(lineStr)
                                        : (nil, lineStr)
                                    continuation.yield(
                                        DockerLogLine(stream: .stdout, message: msg, timestamp: ts))
                                }
                            }
                        }
                    }

                    // Flush remaining buffer for raw TTY
                    if isMultiplexed == false, !buffer.isEmpty,
                        let text = String(data: buffer, encoding: .utf8), !text.isEmpty
                    {
                        let (ts, msg) = timestamps ? Self.splitTimestamp(text) : (nil, text)
                        continuation.yield(
                            DockerLogLine(stream: .stdout, message: msg, timestamp: ts))
                    }

                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Raw HTTP request for container logs, returns collected body data.
    private func rawContainerLogsRequest(
        id: String,
        follow: Bool,
        tail: Int,
        timestamps: Bool,
        since: Int = 0
    ) async throws -> Data {
        let response = try await rawContainerLogsHTTPResponse(
            id: id, follow: follow, tail: tail, timestamps: timestamps, since: since
        )

        var data = Data()
        for try await var chunk in response.body {
            if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    /// Raw HTTP request for container logs, returns the HTTP response for streaming.
    private func rawContainerLogsHTTPResponse(
        id: String,
        follow: Bool,
        tail: Int,
        timestamps: Bool,
        since: Int = 0
    ) async throws -> HTTPClientResponse {
        let encodedSocket =
            socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let path =
            Self.defaultServerURL.path
            + "/containers/\(encodedID)/logs"
            + "?stdout=true&stderr=true"
            + "&follow=\(follow)"
            + "&tail=\(tail)"
            + "&timestamps=\(timestamps)"
            + (since > 0 ? "&since=\(since)" : "")
        let urlString = "http+unix://\(encodedSocket)\(path)"

        var request = HTTPClientRequest(url: urlString)
        request.method = .GET

        let streamTimeout: TimeAmount = follow ? .hours(24) : timeout
        let response = try await httpClient.execute(request, timeout: streamTimeout)
        guard (200..<300).contains(response.status.code) else {
            throw DockerClientError.invalidHTTPStatus(Int(response.status.code))
        }
        return response
    }

    /// Detect whether data uses Docker's multiplexed stream format.
    /// Multiplexed frames have: byte 0 = stream type (0-2), bytes 1-3 = 0, bytes 4-7 = payload size BE.
    /// TTY containers send raw UTF-8 text without framing.
    static func isMultiplexedStream(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let streamByte = data[data.startIndex]
        guard streamByte <= 2 else { return false }
        guard data[data.startIndex + 1] == 0,
            data[data.startIndex + 2] == 0,
            data[data.startIndex + 3] == 0
        else { return false }
        let sizeBytes = data[data.startIndex + 4..<data.startIndex + 8]
        let payloadSize = Int(
            UInt32(sizeBytes[sizeBytes.startIndex]) << 24
                | UInt32(sizeBytes[sizeBytes.startIndex + 1]) << 16
                | UInt32(sizeBytes[sizeBytes.startIndex + 2]) << 8
                | UInt32(sizeBytes[sizeBytes.startIndex + 3])
        )
        return payloadSize > 0 && payloadSize <= data.count - 8
    }

    /// Parse Docker log output, auto-detecting multiplexed vs raw TTY format.
    static func parseMultiplexedStream(_ data: Data, timestamps: Bool) -> [DockerLogLine] {
        if isMultiplexedStream(data) {
            return parseMultiplexedFrames(data, timestamps: timestamps)
        } else {
            return parseRawStream(data, timestamps: timestamps)
        }
    }

    /// Parse Docker multiplexed stream format into log lines.
    ///
    /// Each frame: 8-byte header (byte 0 = stream type, bytes 4-7 = payload size BE) + payload.
    static func parseMultiplexedFrames(_ data: Data, timestamps: Bool) -> [DockerLogLine] {
        var lines: [DockerLogLine] = []
        var offset = data.startIndex

        while offset + 8 <= data.endIndex {
            let streamByte = data[offset]
            let sizeBytes = data[offset + 4..<offset + 8]
            let payloadSize = Int(
                UInt32(sizeBytes[sizeBytes.startIndex]) << 24
                    | UInt32(sizeBytes[sizeBytes.startIndex + 1]) << 16
                    | UInt32(sizeBytes[sizeBytes.startIndex + 2]) << 8
                    | UInt32(sizeBytes[sizeBytes.startIndex + 3])
            )

            guard offset + 8 + payloadSize <= data.endIndex else { break }

            let payload = data[offset + 8..<offset + 8 + payloadSize]
            offset += 8 + payloadSize

            let stream: DockerLogLine.Stream = streamByte == 2 ? .stderr : .stdout

            guard let text = String(data: payload, encoding: .utf8) else { continue }
            let splitLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for line in splitLines {
                let lineStr = String(line)
                if lineStr.isEmpty { continue }
                let (ts, msg) = timestamps ? splitTimestamp(lineStr) : (nil, lineStr)
                lines.append(DockerLogLine(stream: stream, message: msg, timestamp: ts))
            }
        }

        return lines
    }

    /// Parse raw TTY stream (no multiplexing) into log lines, treating all output as stdout.
    static func parseRawStream(_ data: Data, timestamps: Bool) -> [DockerLogLine] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var lines: [DockerLogLine] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            if lineStr.isEmpty { continue }
            let (ts, msg) = timestamps ? splitTimestamp(lineStr) : (nil, lineStr)
            lines.append(DockerLogLine(stream: .stdout, message: msg, timestamp: ts))
        }
        return lines
    }

    /// Split a Docker log line into timestamp and message.
    /// Docker timestamps look like: "2024-01-15T10:23:45.123456789Z message here"
    static func splitTimestamp(_ line: String) -> (timestamp: String?, message: String) {
        // Docker timestamps end with 'Z' and are followed by a space
        guard let spaceIndex = line.firstIndex(of: " "),
            line[line.startIndex..<spaceIndex].hasSuffix("Z")
        else {
            return (nil, line)
        }
        let timestamp = String(line[line.startIndex..<spaceIndex])
        let message = String(line[line.index(after: spaceIndex)...])
        return (timestamp, message)
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

    private static func extractStringMap(_ value: Any?) -> [String: String]? {
        guard let raw = value as? [String: Any] else { return nil }
        var normalizedMap: [String: String] = [:]
        normalizedMap.reserveCapacity(raw.count)
        for (key, val) in raw {
            if let stringValue = normalized(val as? String) {
                normalizedMap[key] = stringValue
            }
        }
        return normalizedMap
    }
}
