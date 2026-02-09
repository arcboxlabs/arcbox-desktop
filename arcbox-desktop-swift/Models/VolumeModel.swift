import Foundation

/// Volume view model for UI display
struct VolumeViewModel: Identifiable, Hashable {
    let name: String
    let driver: String
    let mountPoint: String
    let sizeBytes: UInt64?
    let createdAt: Date
    let inUse: Bool
    let containerNames: [String]

    var id: String { name }

    var sizeDisplay: String {
        guard let bytes = sizeBytes else { return "N/A" }
        let mb = Double(bytes) / 1_000_000.0
        if mb >= 1000.0 {
            return String(format: "%.1f GB", mb / 1000.0)
        } else if mb >= 1.0 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.0f KB", Double(bytes) / 1000.0)
        }
    }

    var createdAgo: String {
        relativeTime(from: createdAt)
    }

    var usageDisplay: String {
        if inUse {
            if containerNames.count == 1 {
                return "Used by \(containerNames[0])"
            }
            return "Used by \(containerNames.count) containers"
        }
        return "Unused"
    }
}
