import Foundation

/// Template view model for UI display
struct TemplateViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let cpuCount: Int
    let memoryMB: Int
    let createdAt: Date
    let updatedAt: Date
    let sandboxCount: Int

    var shortID: String {
        String(id.prefix(12))
    }

    var createdAgo: String {
        relativeTime(from: createdAt)
    }

    var updatedAgo: String {
        relativeTime(from: updatedAt)
    }

    var cpuDisplay: String {
        "\(cpuCount) vCPU"
    }

    var memoryDisplay: String {
        if memoryMB >= 1024 {
            return "\(memoryMB / 1024) GB"
        }
        return "\(memoryMB) MB"
    }

    var sandboxCountDisplay: String {
        switch sandboxCount {
        case 0: "No sandboxes"
        case 1: "1 sandbox"
        default: "\(sandboxCount) sandboxes"
        }
    }
}
