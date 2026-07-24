import FleetPlatformClient

extension FleetMachineStatus {
    var displayName: String {
        switch self {
        case .enrolled: "Enrolled"
        case .online: "Online"
        case .offline: "Offline"
        case .draining: "Draining"
        case .decommissioned: "Decommissioned"
        }
    }
}
