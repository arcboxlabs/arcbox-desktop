import FleetControlClient

extension FleetBackend {
    var displayName: String {
        switch self {
        case .hostRunner: "Host"
        case .docker: "Docker"
        case .vm: "VM"
        case .unspecified, .unrecognized: "Unknown"
        }
    }
}
