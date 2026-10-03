import ArcBoxClient
import Foundation
import SwiftProtobuf

/// Sandbox lifecycle state matching the arcbox.sandbox.v1 API state machine.
enum SandboxState: String, CaseIterable {
    case starting
    case ready
    case running
    case stopping
    case stopped
    case failed
    case pausing
    case paused
    case unknown

    var label: String {
        switch self {
        case .starting: "Starting"
        case .ready: "Ready"
        case .running: "Running"
        case .stopping: "Stopping"
        case .stopped: "Stopped"
        case .failed: "Failed"
        case .pausing: "Pausing"
        case .paused: "Paused"
        case .unknown: "Unknown"
        }
    }

    /// Whether the sandbox VM is alive.
    var isActive: Bool {
        switch self {
        case .starting, .ready, .running:
            true
        default:
            false
        }
    }

    var isDataPlaneReady: Bool {
        self == .ready || self == .running
    }

    /// Whether the sandbox can accept a new execution right now.
    var isAcceptingCommands: Bool {
        self == .ready
    }

    var canRemove: Bool {
        self == .stopped || self == .failed || self == .paused
    }

    init(apiState: Arcbox_Sandbox_V1_SandboxState) {
        switch apiState {
        case .starting: self = .starting
        case .ready: self = .ready
        case .running: self = .running
        case .stopping: self = .stopping
        case .stopped: self = .stopped
        case .failed: self = .failed
        case .pausing: self = .pausing
        case .paused: self = .paused
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}

enum SandboxExitStatus: Hashable {
    case code(Int32)
    case signal(Int32)

    init?(apiStatus: Arcbox_Sandbox_V1_ExitStatus, isPresent: Bool) {
        guard isPresent, let status = apiStatus.status else { return nil }
        switch status {
        case .code(let code): self = .code(code)
        case .signal(let signal): self = .signal(signal)
        }
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
    var lastExitStatus: SandboxExitStatus?
    var error: String
    var vcpus: UInt32
    var memoryMiB: UInt64
    var isTransitioning: Bool = false
    /// Whether detail fields (vcpus, memory, readyAt, error, …) were loaded via Inspect.
    var hasLoadedDetail: Bool = false

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

    init(from summary: Arcbox_Sandbox_V1_SandboxSummary) {
        self.id = summary.id
        self.state = SandboxState(apiState: summary.state)
        self.labels = summary.labels
        self.ipAddress = summary.ipAddress
        self.createdAt = summary.hasCreatedAt ? summary.createdAt.date : nil
        self.readyAt = nil
        self.lastExitedAt = nil
        self.lastExitStatus = nil
        self.error = ""
        self.vcpus = 0
        self.memoryMiB = 0
    }

    init(from info: Arcbox_Sandbox_V1_SandboxInfo) {
        self.id = info.id
        self.state = SandboxState(apiState: info.state)
        self.labels = info.labels
        self.ipAddress = info.network.ipAddress
        self.createdAt = info.hasCreatedAt ? info.createdAt.date : nil
        self.readyAt = info.hasReadyAt ? info.readyAt.date : nil
        self.lastExitedAt = info.hasLastExitedAt ? info.lastExitedAt.date : nil
        self.lastExitStatus = SandboxExitStatus(
            apiStatus: info.lastExitStatus,
            isPresent: info.hasLastExitStatus
        )
        self.error = info.error
        self.vcpus = info.limits.vcpus
        self.memoryMiB = info.limits.memoryMib
    }

    /// Apply detail fields from an Inspect response, preserving list-level fields.
    mutating func applyDetails(from info: Arcbox_Sandbox_V1_SandboxInfo) {
        self.state = SandboxState(apiState: info.state)
        self.ipAddress = info.network.ipAddress
        self.readyAt = info.hasReadyAt ? info.readyAt.date : nil
        self.lastExitedAt = info.hasLastExitedAt ? info.lastExitedAt.date : nil
        self.lastExitStatus = SandboxExitStatus(
            apiStatus: info.lastExitStatus,
            isPresent: info.hasLastExitStatus
        )
        self.error = info.error
        self.vcpus = info.limits.vcpus
        self.memoryMiB = info.limits.memoryMib
        self.hasLoadedDetail = true
    }

    /// Copy detail-only fields from a previously-inspected model so a list refresh
    /// does not wipe data the summary endpoint does not return.
    mutating func preserveDetailFrom(_ other: SandboxViewModel) {
        guard other.hasLoadedDetail else { return }
        self.readyAt = other.readyAt
        self.lastExitedAt = other.lastExitedAt
        self.lastExitStatus = other.lastExitStatus
        self.error = other.error
        self.vcpus = other.vcpus
        self.memoryMiB = other.memoryMiB
        self.hasLoadedDetail = true
    }
}

/// Snapshot view model for the per-sandbox Snapshots tab.
struct SandboxSnapshotViewModel: Identifiable, Hashable {
    let id: String
    let sandboxID: String
    let name: String
    let labels: [String: String]
    let createdAt: Date?

    var displayName: String {
        name.isEmpty ? String(id.prefix(12)) : name
    }

    var createdAgo: String {
        guard let createdAt else { return "—" }
        return relativeTime(from: createdAt)
    }

    init(from summary: Arcbox_Sandbox_V1_SnapshotSummary) {
        self.id = summary.id
        self.sandboxID = summary.sandboxID
        self.name = summary.name
        self.labels = summary.labels
        self.createdAt = summary.hasCreatedAt ? summary.createdAt.date : nil
    }
}

/// A catalog template: a named, versioned base for sandboxes.
///
/// `TemplateService.List` returns one entry per *version*, drafts included, so
/// several entries can share a name. `reference` is what distinguishes them and
/// what `CreateSandboxRequest.template` takes.
struct SandboxTemplateViewModel: Identifiable, Hashable {
    let name: String
    /// Empty for an unpublished draft.
    let version: String
    let digest: String
    /// Pre-warmed boot-to-ready snapshot; empty means a cold boot.
    let warmSnapshotID: String
    let createdAt: Date?
    let labels: [String: String]
    let sizeBytes: UInt64
    let defaultVcpus: UInt32
    let defaultMemoryMiB: UInt64
    let defaultCmd: [String]
    let exposedPorts: [UInt32]
    let hasReadyProbe: Bool

    /// `name:version`, or the bare name for a draft. Doubles as the value
    /// `CreateSandboxRequest.template` resolves against the catalog.
    var reference: String {
        version.isEmpty ? name : "\(name):\(version)"
    }

    var id: String { reference }

    var isDraft: Bool { version.isEmpty }

    /// Restores from a memory image instead of booting, so READY is sub-second.
    var isWarm: Bool { !warmSnapshotID.isEmpty }

    var displayVersion: String {
        version.isEmpty ? "draft" : version
    }

    var createdAgo: String {
        guard let createdAt else { return "—" }
        return relativeTime(from: createdAt)
    }

    var formattedSize: String {
        formattedBytes(Int64(clamping: sizeBytes))
    }

    init(from template: Arcbox_Sandbox_V1_Template) {
        self.name = template.name
        self.version = template.version
        self.digest = template.digest
        self.warmSnapshotID = template.warmSnapshotID
        self.createdAt = template.hasCreatedAt ? template.createdAt.date : nil
        self.labels = template.labels
        self.sizeBytes = template.sizeBytes
        let defaults = template.defaults
        self.defaultVcpus = defaults.limits.vcpus
        self.defaultMemoryMiB = defaults.limits.memoryMib
        self.defaultCmd = defaults.cmd
        self.exposedPorts = defaults.exposedPorts
        self.hasReadyProbe = defaults.hasReadyProbe
    }
}

/// A host listener currently owned by a sandbox.
struct SandboxExposedPort: Identifiable, Hashable {
    let sandboxPort: UInt32
    let hostPort: UInt32
    let networkProtocol: String

    var id: String { "\(networkProtocol):\(sandboxPort)" }

    var localURL: URL? {
        URL(string: "http://localhost:\(hostPort)")
    }
}

enum SandboxEventKind: Hashable {
    case created
    case ready
    case running
    case idle
    case stopping
    case stopped
    case failed
    case removed
    case pausing
    case paused
    case resumed
    case unknown

    var label: String {
        switch self {
        case .created: "created"
        case .ready: "ready"
        case .running: "running"
        case .idle: "idle"
        case .stopping: "stopping"
        case .stopped: "stopped"
        case .failed: "failed"
        case .removed: "removed"
        case .pausing: "pausing"
        case .paused: "paused"
        case .resumed: "resumed"
        case .unknown: "unknown"
        }
    }

    init(apiKind: Arcbox_Sandbox_V1_SandboxEventKind) {
        switch apiKind {
        case .created: self = .created
        case .ready: self = .ready
        case .running: self = .running
        case .idle: self = .idle
        case .stopping: self = .stopping
        case .stopped: self = .stopped
        case .failed: self = .failed
        case .removed: self = .removed
        case .pausing: self = .pausing
        case .paused: self = .paused
        case .resumed: self = .resumed
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}

/// A lifecycle event received on the Events stream, kept for the Events tab.
struct SandboxEventRecord: Identifiable, Hashable {
    let id = UUID()
    let sandboxID: String
    let kind: SandboxEventKind
    let timestamp: Date
    let attributes: [String: String]

    var action: String {
        kind.label
    }

    init(sandboxID: String, kind: SandboxEventKind, timestamp: Date, attributes: [String: String] = [:]) {
        self.sandboxID = sandboxID
        self.kind = kind
        self.timestamp = timestamp
        self.attributes = attributes
    }

    init(from event: Arcbox_Sandbox_V1_SandboxEvent) {
        self.init(
            sandboxID: event.sandboxID,
            kind: SandboxEventKind(apiKind: event.kind),
            timestamp: event.time.date,
            attributes: event.attributes
        )
    }
}
