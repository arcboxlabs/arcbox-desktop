import Foundation

/// Shared utility for relative time display
func relativeTime(from date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    let days = Int(interval / 86400)
    let hours = Int(interval / 3600)
    let minutes = Int(interval / 60)

    if days >= 30 {
        let months = days / 30
        return "\(months) month\(months > 1 ? "s" : "") ago"
    } else if days >= 7 {
        let weeks = days / 7
        return "\(weeks) week\(weeks > 1 ? "s" : "") ago"
    } else if days > 0 {
        return "\(days) day\(days > 1 ? "s" : "") ago"
    } else if hours > 0 {
        return "\(hours) hour\(hours > 1 ? "s" : "") ago"
    } else if minutes > 0 {
        return "\(minutes) minute\(minutes > 1 ? "s" : "") ago"
    }
    return "just now"
}
