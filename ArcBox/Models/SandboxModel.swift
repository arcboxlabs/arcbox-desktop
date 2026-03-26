import ArcBoxClient
import Foundation

/// Sandbox lifecycle state matching the API state machine.
enum SandboxState: String, CaseIterable {
    case starting
    case ready
    case running
    case idle
    case stopping
    case stopped
    case failed
    case removed
    case unknown

    var label: String {
        switch self {
        case .starting: "Starting"
        case .ready: "Ready"
        case .running: "Running"
        case .idle: "Idle"
        case .stopping: "Stopping"
        case .stopped: "Stopped"
        case .failed: "Failed"
        case .removed: "Removed"
        case .unknown: "Unknown"
        }
    }

    /// Whether the sandbox is alive and accepting commands.
    var isActive: Bool {
        switch self {
        case .starting, .ready, .running, .idle:
            true
        default:
            false
        }
    }

    /// Whether the sandbox can accept Run/Exec calls.
    var isAcceptingCommands: Bool {
        self == .ready || self == .idle
    }

    init(apiState: String) {
        self = SandboxState(rawValue: apiState) ?? .unknown
    }
}

/// Sandbox view model for UI display.
struct SandboxViewModel: Identifiable, Hashable {
    let id: String
    var state: SandboxState
    var labels: [String: String]
    var ipAddress: String
    var createdAt: Date?
    var readyAt: Date?
    var lastExitedAt: Date?
    var lastExitCode: Int32
    var error: String
    var vcpus: UInt32
    var memoryMiB: UInt64
    var isTransitioning: Bool = false

    var shortID: String {
        String(id.prefix(12))
    }

    var displayName: String {
        labels["name"] ?? shortID
    }

    var createdAgo: String {
        guard let createdAt else { return "—" }
        return relativeTime(from: createdAt)
    }

    var cpuDisplay: String {
        vcpus == 0 ? "default" : "\(vcpus) vCPU"
    }

    var memoryDisplay: String {
        if memoryMiB == 0 { return "default" }
        if memoryMiB >= 1024 {
            return "\(memoryMiB / 1024) GB"
        }
        return "\(memoryMiB) MB"
    }

    // MARK: - Proto initializers

    init(from summary: Sandbox_V1_SandboxSummary) {
        self.id = summary.id
        self.state = SandboxState(apiState: summary.state)
        self.labels = summary.labels
        self.ipAddress = summary.ipAddress
        self.createdAt = summary.createdAt > 0
            ? Date(timeIntervalSince1970: TimeInterval(summary.createdAt))
            : nil
        self.readyAt = nil
        self.lastExitedAt = nil
        self.lastExitCode = 0
        self.error = ""
        self.vcpus = 0
        self.memoryMiB = 0
    }

    init(from info: Sandbox_V1_SandboxInfo) {
        self.id = info.id
        self.state = SandboxState(apiState: info.state)
        self.labels = info.labels
        self.ipAddress = info.network.ipAddress
        self.createdAt = info.createdAt > 0
            ? Date(timeIntervalSince1970: TimeInterval(info.createdAt))
            : nil
        self.readyAt = info.readyAt > 0
            ? Date(timeIntervalSince1970: TimeInterval(info.readyAt))
            : nil
        self.lastExitedAt = info.lastExitedAt > 0
            ? Date(timeIntervalSince1970: TimeInterval(info.lastExitedAt))
            : nil
        self.lastExitCode = info.lastExitCode
        self.error = info.error
        self.vcpus = info.limits.vcpus
        self.memoryMiB = info.limits.memoryMib
    }

    /// Apply detail fields from an inspect response, preserving list-level fields.
    mutating func applyDetails(from info: Sandbox_V1_SandboxInfo) {
        self.state = SandboxState(apiState: info.state)
        self.ipAddress = info.network.ipAddress
        self.readyAt = info.readyAt > 0
            ? Date(timeIntervalSince1970: TimeInterval(info.readyAt))
            : nil
        self.lastExitedAt = info.lastExitedAt > 0
            ? Date(timeIntervalSince1970: TimeInterval(info.lastExitedAt))
            : nil
        self.lastExitCode = info.lastExitCode
        self.error = info.error
        self.vcpus = info.limits.vcpus
        self.memoryMiB = info.limits.memoryMib
    }
}
