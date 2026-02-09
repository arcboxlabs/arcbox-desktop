import SwiftUI

/// Navigation item in sidebar
enum NavItem: String, CaseIterable, Identifiable {
    case containers
    case volumes
    case images
    case networks
    case machines

    var id: String { rawValue }

    var label: String {
        switch self {
        case .containers: "Containers"
        case .volumes: "Volumes"
        case .images: "Images"
        case .networks: "Networks"
        case .machines: "Machines"
        }
    }

    var sfSymbol: String {
        switch self {
        case .containers: "arrow.triangle.2.circlepath"
        case .volumes: "internaldrive"
        case .images: "circle.dotted.circle"
        case .networks: "network"
        case .machines: "desktopcomputer"
        }
    }

    /// Sidebar sections
    enum Section: String, CaseIterable, Identifiable {
        case docker = "DOCKER"
        case linux = "LINUX"

        var id: String { rawValue }

        var items: [NavItem] {
            switch self {
            case .docker: [.containers, .volumes, .images, .networks]
            case .linux: [.machines]
            }
        }
    }
}
