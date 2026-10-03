import Foundation

/// Filter for log streams
enum LogStreamFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case stdout = "Stdout"
    case stderr = "Stderr"

    var id: String { rawValue }
}

/// Which stream a log line came from
enum LogStream {
    case stdout
    case stderr
}

/// A single log entry with metadata
struct LogEntry: Identifiable {
    let id = UUID()
    /// The raw Docker timestamp, which is what `Copy logs` writes out.
    let timestamp: String?
    /// `timestamp` as local wall-clock time, resolved once here. The view body runs for
    /// every row on every new line, and `ISO8601DateFormatter` is far too slow to sit in
    /// that path — doing so hung the app on containers that log steadily.
    let time: String?
    let stream: LogStream
    let message: String

    init(timestamp: String?, stream: LogStream, message: String) {
        self.timestamp = timestamp
        self.time = timestamp.map(LogTimestamp.localTime)
        self.stream = stream
        self.message = message
    }
}

enum LogTimestamp {
    /// Docker writes RFC3339Nano; `ISO8601DateFormatter` accepts at most milliseconds, so
    /// the fractional part is trimmed before parsing rather than left to fail into the
    /// fallback on every line.
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    /// Renders `HH:mm:ss` in the local timezone, falling back to the timestamp's own time
    /// field when it is not a shape we can parse.
    static func localTime(_ timestamp: String) -> String {
        if let date = isoFormatter.date(from: withoutFractionalSeconds(timestamp)) {
            return displayFormatter.string(from: date)
        }
        guard let tIndex = timestamp.firstIndex(of: "T"),
            let end = timestamp.firstIndex(of: "Z") ?? timestamp.lastIndex(of: "+")
        else {
            return timestamp
        }
        let timePart = timestamp[timestamp.index(after: tIndex)..<end]
        guard let dot = timePart.firstIndex(of: ".") else { return String(timePart) }
        return String(timePart[timePart.startIndex..<dot])
    }

    /// `2026-09-19T05:23:45.123456789Z` → `2026-09-19T05:23:45Z`, leaving anything else alone.
    private static func withoutFractionalSeconds(_ timestamp: String) -> String {
        guard let dot = timestamp.firstIndex(of: "."),
            let zone = timestamp[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" })
        else {
            return timestamp
        }
        return String(timestamp[timestamp.startIndex..<dot]) + String(timestamp[zone...])
    }
}
