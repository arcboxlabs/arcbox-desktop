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
    let timestamp: String?
    let stream: LogStream
    let message: String
}
