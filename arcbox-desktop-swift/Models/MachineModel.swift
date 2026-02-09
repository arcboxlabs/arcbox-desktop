import SwiftUI

/// Machine state representation
enum MachineState: String, CaseIterable, Identifiable {
    case running
    case stopped
    case starting
    case stopping

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var isRunning: Bool { self == .running }

    var color: Color {
        switch self {
        case .running: AppColors.running
        case .stopped: AppColors.stopped
        case .starting, .stopping: AppColors.warning
        }
    }
}

/// Linux distribution info
struct DistroInfo: Hashable {
    let name: String
    let version: String
    let displayName: String
}

/// Machine view model for UI display
struct MachineViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let distro: DistroInfo
    let state: MachineState
    let cpuCores: UInt32
    let memoryGB: UInt32
    let diskGB: UInt32
    let ipAddress: String?
    let createdAt: Date

    var isRunning: Bool { state.isRunning }

    var resourcesDisplay: String {
        "\(cpuCores) cores, \(memoryGB) GB RAM, \(diskGB) GB disk"
    }
}
