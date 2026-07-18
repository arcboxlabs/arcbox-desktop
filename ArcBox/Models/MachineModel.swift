import ArcBoxClient
import SwiftUI

/// Machine state representation.
///
/// Mirrors the daemon's wire strings (`format!("{:?}").to_lowercase()` of
/// arcbox-core's `MachineState`).
enum MachineState: String, CaseIterable, Identifiable {
    case created
    case starting
    case running
    case stopping
    case stopped

    init(apiState: String) {
        self = MachineState(rawValue: apiState) ?? .stopped
    }

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var isRunning: Bool { self == .running }

    var color: Color {
        switch self {
        case .running: AppColors.running
        case .created, .stopped: AppColors.stopped
        case .starting, .stopping: AppColors.warning
        }
    }
}

/// Linux distribution info
struct DistroInfo: Hashable {
    let name: String
    let version: String
    let displayName: String

    /// Build from wire fields; empty distro means a plain (non-distro) VM.
    init(distro: String, version: String) {
        self.name = distro
        self.version = version
        self.displayName = distro.isEmpty ? "Linux" : distro.capitalized
    }
}

/// A directory shared into a machine.
struct MachineMountViewModel: Hashable, Identifiable {
    let hostPath: String
    let guestPath: String
    let readOnly: Bool

    var id: String { "\(hostPath):\(guestPath)" }

    init(from mount: Arcbox_V1_DirectoryMount) {
        self.hostPath = mount.hostPath
        self.guestPath = mount.guestPath
        self.readOnly = mount.readonly
    }
}

/// Machine view model for UI display
struct MachineViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    var distro: DistroInfo
    var state: MachineState
    var cpuCores: UInt32
    var memoryGB: UInt32
    var diskGB: UInt32
    var architecture: String
    var ipAddress: String?
    var createdAt: Date

    // Detail fields populated by Inspect (empty until loaded).
    var gateway: String = ""
    var macAddress: String = ""
    var dnsServers: [String] = []
    var mounts: [MachineMountViewModel] = []
    var startedAt: Date?

    /// A lifecycle RPC is in flight for this machine.
    var isTransitioning: Bool = false

    var isRunning: Bool { state.isRunning }

    var resourcesDisplay: String {
        "\(cpuCores) cores, \(memoryGB) GB RAM, \(diskGB) GB disk"
    }

    init(from summary: Arcbox_V1_MachineSummary) {
        self.id = summary.id
        self.name = summary.name
        self.distro = DistroInfo(distro: summary.distro, version: summary.distroVersion)
        self.state = MachineState(apiState: summary.state)
        self.cpuCores = summary.cpus
        self.memoryGB = Self.gigabytes(summary.memory)
        self.diskGB = Self.gigabytes(summary.diskSize)
        self.architecture = ""
        self.ipAddress = summary.ipAddress.isEmpty ? nil : summary.ipAddress
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(summary.created))
    }

    /// Merge Inspect-only fields into a summary-built view model.
    mutating func applyDetails(from info: Arcbox_V1_MachineInfo) {
        architecture = info.hardware.arch
        gateway = info.network.gateway
        macAddress = info.network.macAddress
        dnsServers = info.network.dnsServers
        mounts = info.mounts.map(MachineMountViewModel.init(from:))
        if info.hasStartedAt, info.startedAt.seconds > 0 {
            startedAt = Date(timeIntervalSince1970: TimeInterval(info.startedAt.seconds))
        }
    }

    /// Preserve detail fields across a list refresh, which only carries
    /// summary data.
    mutating func preserveDetailFrom(_ existing: MachineViewModel) {
        architecture = existing.architecture
        gateway = existing.gateway
        macAddress = existing.macAddress
        dnsServers = existing.dnsServers
        mounts = existing.mounts
        startedAt = existing.startedAt
    }

    private static func gigabytes(_ bytes: UInt64) -> UInt32 {
        UInt32((bytes + (1 << 29)) >> 30)
    }
}
