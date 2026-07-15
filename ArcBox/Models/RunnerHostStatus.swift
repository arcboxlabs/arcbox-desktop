import FleetControlClient
import SwiftUI

/// User-facing state derived from the local Fleet Agent watch snapshot.
enum RunnerHostStatus: Equatable {
    case attaching
    case online
    case draining
    case updating
    case detached
    case credentialRejected
    case unknown

    init(snapshot: FleetAgentSnapshot) {
        switch snapshot.enrollment {
        case .attaching:
            self = .attaching
        case .attached:
            self = snapshot.isDraining ? .draining : .online
        case .updating:
            self = .updating
        case .detached:
            self = .detached
        case .credentialRejected:
            self = .credentialRejected
        case .unspecified, .unenrolled, .unrecognized:
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .attaching: "Attaching"
        case .online: "Online"
        case .draining: "Draining"
        case .updating: "Updating"
        case .detached: "Detached"
        case .credentialRejected: "Credential Rejected"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .online: AppColors.running
        case .attaching, .draining, .updating: AppColors.warning
        case .detached, .credentialRejected, .unknown: AppColors.stopped
        }
    }

    var canChangeDrainState: Bool {
        self == .online || self == .draining
    }
}
