import SwiftUI

/// Navigation item in sidebar
enum NavItem: String, CaseIterable, Identifiable {
    case containers
    case volumes
    case images
    case networks
    case pods
    case services
    case machines
    case sandboxes
    case templates

    var id: String { rawValue }

    /// Whether this item belongs to a not-yet-implemented section.
    var isComingSoon: Bool {
        switch self {
        case .pods, .services, .machines, .sandboxes, .templates:
            true
        default:
            false
        }
    }

    var label: String {
        switch self {
        case .containers: "Containers"
        case .volumes: "Volumes"
        case .images: "Images"
        case .networks: "Networks"
        case .pods: "Pods"
        case .services: "Services"
        case .machines: "Machines"
        case .sandboxes: "Sandboxes"
        case .templates: "Templates"
        }
    }

    var sfSymbol: String {
        switch self {
        case .containers: "cube"
        case .volumes: "internaldrive"
        case .images: "circle.circle"
        case .networks: "point.3.filled.connected.trianglepath.dotted"
        case .pods: "helm"
        case .services: "gearshape.2"
        case .machines: "desktopcomputer"
        case .sandboxes: "server.rack"
        case .templates: "doc.on.doc"
        }
    }

    /// Sidebar sections
    enum Section: String, CaseIterable, Identifiable {
        case docker = "DOCKER"
        case kubernetes = "KUBERNETES"
        case linux = "LINUX"
        case sandbox = "SANDBOX"

        var id: String { rawValue }

        var items: [NavItem] {
            switch self {
            case .docker: [.containers, .volumes, .images, .networks]
            case .kubernetes: [.pods, .services]
            case .linux: [.machines]
            case .sandbox: [.sandboxes, .templates]
            }
        }
    }
}
