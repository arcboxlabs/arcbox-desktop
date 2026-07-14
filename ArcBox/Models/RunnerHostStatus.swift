import FleetControlClient
import SwiftUI

/// User-facing state derived from the local Fleet Agent watch snapshot.
enum RunnerHostStatus: Equatable {
    case connecting
    case online
    case draining
    case detached
    case credentialRejected
    case unknown

    init(snapshot: FleetAgentSnapshot) {
        switch snapshot.enrollment {
        case .attaching:
            self = .connecting
        case .attached:
            self = snapshot.isDraining ? .draining : .online
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
        case .connecting: "Connecting"
        case .online: "Online"
        case .draining: "Draining"
        case .detached: "Detached"
        case .credentialRejected: "Credential Rejected"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .online: AppColors.running
        case .connecting, .draining: AppColors.warning
        case .detached, .credentialRejected, .unknown: AppColors.stopped
        }
    }

    var canChangeDrainState: Bool {
        self == .online || self == .draining
    }
}
