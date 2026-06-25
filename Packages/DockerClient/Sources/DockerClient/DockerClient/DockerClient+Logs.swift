import AsyncHTTPClient
import Foundation
import NIOCore
import OSLog

extension DockerClient {
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

        /// Maximum body size for batch log fetch (50 MB).
        let maxBodySize = 50 * 1024 * 1024
        var data = Data()
        var truncated = false
        for try await var chunk in response.body {
            if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                data.append(contentsOf: bytes)
            }
            if data.count > maxBodySize {
                truncated = true
                break
            }
        }
        if truncated {
            Logger(subsystem: "com.arcboxlabs.desktop", category: "docker")
                .warning("Container \(id) logs truncated at \(maxBodySize) bytes")
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

    /// Gracefully shut down the underlying HTTP client.
    public func shutdown() async throws {
        try await httpClient.shutdown()
    }

}
