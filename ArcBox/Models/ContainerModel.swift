import Foundation
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

/// Mount info for container detail display
struct ContainerMount: Hashable, Identifiable {
    var id: String { "\(type):\(source)->\(destination):\(isReadOnly)" }
    let type: String
    let source: String
    let destination: String
    let isReadOnly: Bool
}

/// Container view model for UI display
struct ContainerViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    var state: ContainerState
    var isTransitioning: Bool = false
    let ports: [PortMapping]
    let createdAt: Date
    let composeProject: String?
    let labels: [String: String]
    var cpuPercent: Double
    var memoryMB: Double
    var memoryLimitMB: Double
    var domain: String?
    var ipAddress: String?
    var mounts: [ContainerMount] = []
    var rootfsMountPath: String?

    var isRunning: Bool { state.isRunning }

    static let rootfsMountPathLabelKeys = [
        "arcbox.rootfs.mount.path",
        "com.arcbox.rootfs.mount.path",
        "arcbox.rootfs.path",
        "com.arcbox.rootfs.path",
        "rootfs.mount.path",
    ]

    var preferredRootFSMountPath: String? {
        Self.inferRootFSMountPath(
            explicitPath: rootfsMountPath,
            labels: labels,
            mounts: mounts
        )
    }

    var resolvedRootFSMountPath: String? {
        preferredRootFSMountPath
    }

    static func inferRootFSMountPath(
        explicitPath: String?,
        labels: [String: String],
        mounts: [ContainerMount]
    ) -> String? {
        if let explicitPath = normalizedPath(explicitPath) {
            return explicitPath
        }

        for key in rootfsMountPathLabelKeys {
            if let labelPath = normalizedPath(labels[key]) {
                return labelPath
            }
        }

        if let rootMount = mounts.first(where: { $0.destination == "/" }),
           let sourcePath = normalizedPath(rootMount.source)
        {
            return sourcePath
        }

        return nil
    }

    var hostPorts: [UInt16] {
        ports.compactMap { $0.hostPort > 0 ? $0.hostPort : nil }
    }

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
        lhs.id == rhs.id && lhs.state == rhs.state && lhs.isTransitioning == rhs.isTransitioning
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/") else { return nil }
        return trimmed
    }

}
