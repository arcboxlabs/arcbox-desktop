import Foundation

/// Network view model for UI display
struct NetworkViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let driver: String
    let scope: String
    let createdAt: Date
    let `internal`: Bool
    let attachable: Bool
    let containerCount: Int

    var shortID: String {
        String(id.prefix(12))
    }

    var createdAgo: String {
        relativeTime(from: createdAt)
    }

    var driverDisplay: String {
        "\(driver) (\(scope))"
    }

    var usageDisplay: String {
        switch containerCount {
        case 0: "No containers"
        case 1: "1 container"
        default: "\(containerCount) containers"
        }
    }

    var isSystem: Bool {
        ["bridge", "host", "none"].contains(name)
    }
}
