enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case account = "Account"
    case system = "System"
    case fleet = "Fleet"
    case storage = "Storage"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .general: "gearshape"
        case .account: "person.circle"
        case .system: "square.grid.2x2"
        case .fleet: "server.rack"
        case .storage: "externaldrive"
        }
    }
}
