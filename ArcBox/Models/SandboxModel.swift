import Foundation

/// Sandbox state
enum SandboxState: String {
    case running
    case paused
    case stopped

    var label: String {
        switch self {
        case .running: "Running"
        case .paused: "Paused"
        case .stopped: "Stopped"
        }
    }
}

/// Sandbox view model for UI display
struct SandboxViewModel: Identifiable, Hashable {
    let id: String
    let alias: String
    let templateID: String
    let state: SandboxState
    let cpuCount: Int
    let memoryMB: Int
    let startedAt: Date
    let endAt: Date

    var isRunning: Bool { state == .running }

    var shortID: String {
        String(id.prefix(12))
    }

    var startedAgo: String {
        relativeTime(from: startedAt)
    }

    var timeRemaining: String {
        let remaining = endAt.timeIntervalSince(Date())
        if remaining <= 0 { return "Expired" }
        let minutes = Int(remaining / 60)
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m remaining"
        }
        return "\(minutes)m remaining"
    }

    var cpuDisplay: String {
        "\(cpuCount) vCPU"
    }

    var memoryDisplay: String {
        if memoryMB >= 1024 {
            return "\(memoryMB / 1024) GB"
        }
        return "\(memoryMB) MB"
    }
}
