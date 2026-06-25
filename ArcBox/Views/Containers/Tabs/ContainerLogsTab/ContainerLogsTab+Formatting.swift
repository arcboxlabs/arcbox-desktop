import Foundation

extension ContainerLogsTab {
    /// ISO8601 parser for Docker RFC3339Nano timestamps
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Display formatter in user's local timezone
    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    /// Format Docker RFC3339Nano timestamp to local time
    func formatTimestamp(_ ts: String) -> String {
        if let date = Self.isoFormatter.date(from: ts) {
            return Self.displayFormatter.string(from: date)
        }
        // Fallback: extract time part if parsing fails
        guard let tIndex = ts.firstIndex(of: "T"),
            let zIndex = ts.firstIndex(of: "Z") ?? ts.lastIndex(of: "+")
        else {
            return ts
        }
        let timePart = ts[ts.index(after: tIndex)..<zIndex]
        if let dotIndex = timePart.firstIndex(of: ".") {
            return String(timePart[timePart.startIndex..<dotIndex])
        }
        return String(timePart)
    }
}
