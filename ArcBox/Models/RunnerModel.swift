import SwiftUI

/// Fleet machine status as reported by the platform control plane.
enum RunnerHostStatus: String, CaseIterable, Identifiable {
    case enrolling
    case online
    case offline
    case draining

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .online: AppColors.running
        case .enrolling, .draining: AppColors.warning
        case .offline: AppColors.stopped
        }
    }
}

/// Job slots of one runtime pool on the host.
struct RunnerCapacity: Hashable {
    let used: Int
    let limit: Int

    var display: String { "\(used)/\(limit)" }

    var fraction: Double {
        limit > 0 ? min(1.0, Double(used) / Double(limit)) : 0
    }

    var isSaturated: Bool { limit > 0 && used >= limit }
}

/// This Mac as an enrolled fleet machine, for UI display.
struct RunnerHostViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let fleetName: String
    /// GitHub orgs routed to this host's fleet.
    let orgs: [String]
    var status: RunnerHostStatus
    let chip: String
    /// macOS jobs run as ephemeral vz microVMs.
    var macOSPool: RunnerCapacity
    /// Linux jobs run as Docker containers on the arcbox engine.
    var linuxPool: RunnerCapacity
    let lastSeenAt: Date

    var activeJobCount: Int { macOSPool.used + linuxPool.used }

    var orgsDisplay: String { orgs.joined(separator: ", ") }
}

/// Pre-enrollment preview of what this Mac could contribute as a runner host.
enum RunnerHostCapability {
    /// Marketing name of the chip, e.g. "Apple M3 Max".
    static var chipName: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return "Apple Silicon"
        }
        var brand = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0) == 0 else {
            return "Apple Silicon"
        }
        let bytes = brand.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "Apple Silicon"
    }

    /// Virtualization.framework licensing allows at most two concurrent macOS guests per host.
    static let macOSGuestLimit = 2

    /// Rough default for concurrent Linux job containers, refined after enrollment.
    static var linuxRunnerEstimate: Int {
        max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    }
}
