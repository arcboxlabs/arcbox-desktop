import SwiftUI

/// Container state representation
enum ContainerState: String, CaseIterable, Identifiable {
    case running
    case stopped
    case restarting
    case paused
    case dead

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var isRunning: Bool { self == .running }

    var color: Color {
        switch self {
        case .running: AppColors.running
        case .stopped: AppColors.stopped
        case .restarting, .paused: AppColors.warning
        case .dead: AppColors.error
        }
    }
}

/// Port mapping for container
struct PortMapping: Hashable, Identifiable {
    var id: String { "\(hostPort):\(containerPort)/\(`protocol`)" }
    let hostPort: UInt16
    let containerPort: UInt16
    let `protocol`: String
}

/// Container view model for UI display
struct ContainerViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let state: ContainerState
    let ports: [PortMapping]
    let createdAt: Date
    let composeProject: String?
    let labels: [String: String]
    var cpuPercent: Double
    var memoryMB: Double
    var memoryLimitMB: Double

    var isRunning: Bool { state.isRunning }

    var portsDisplay: String {
        if ports.isEmpty { return "-" }
        return ports.map { "\($0.hostPort):\($0.containerPort)" }.joined(separator: ", ")
    }

    var createdAgo: String {
        let interval = Date().timeIntervalSince(createdAt)
        let days = Int(interval / 86400)
        let hours = Int(interval / 3600)
        let minutes = Int(interval / 60)

        if days > 0 { return "\(days)d ago" }
        if hours > 0 { return "\(hours)h ago" }
        if minutes > 0 { return "\(minutes)m ago" }
        return "just now"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ContainerViewModel, rhs: ContainerViewModel) -> Bool {
        lhs.id == rhs.id
    }
}
