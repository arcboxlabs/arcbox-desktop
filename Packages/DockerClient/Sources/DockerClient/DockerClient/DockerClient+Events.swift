import AsyncHTTPClient
import Foundation

extension DockerClient {
    // MARK: - Docker Events

    /// A single event from the Docker daemon `/events` stream.
    public struct DockerEvent: Sendable {
        public let type: String  // "container", "image", "network", "volume", …
        public let action: String  // "start", "stop", "die", "create", "destroy", …
        public let actorID: String?
        /// The event's `Actor.Attributes`. On a container `die` this carries
        /// `exitCode`, `name` and `image`; Compose-managed containers also
        /// carry their `com.docker.compose.*` labels.
        public let attributes: [String: String]
        /// When the daemon recorded the event.
        public let date: Date

        public init(
            type: String,
            action: String,
            actorID: String?,
            attributes: [String: String] = [:],
            date: Date
        ) {
            self.type = type
            self.action = action
            self.actorID = actorID
            self.attributes = attributes
            self.date = date
        }
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

                    let maxBufferSize = 10 * 1024 * 1024  // 10 MB
                    var buffer = Data()
                    for try await var chunk in response.body {
                        if Task.isCancelled { break }
                        if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                            buffer.append(contentsOf: bytes)
                        }
                        // Prevent OOM from malformed data without newlines.
                        if buffer.count > maxBufferSize {
                            buffer.removeAll()
                            continue
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
                            let attributes = actor?["Attributes"] as? [String: String] ?? [:]
                            // `timeNano` is finer, but at present-day values it
                            // is past the range where a Double holds every
                            // integer, so reading it back loses the precision
                            // it was for. `time` is whole seconds, which is all
                            // any consumer needs.
                            let date = (json["time"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))

                            continuation.yield(
                                DockerEvent(
                                    type: type,
                                    action: action,
                                    actorID: actorID,
                                    attributes: attributes,
                                    date: date ?? Date()
                                ))
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

}
