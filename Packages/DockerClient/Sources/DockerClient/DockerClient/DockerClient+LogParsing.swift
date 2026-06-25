import Foundation

extension DockerClient {
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
}
