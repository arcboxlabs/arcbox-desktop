import Foundation

/// Image view model for UI display
struct ImageViewModel: Identifiable, Hashable {
    let id: String
    let repository: String
    let tag: String
    let sizeBytes: UInt64
    let createdAt: Date
    let inUse: Bool
    let os: String
    let architecture: String

    var fullName: String {
        if repository == "<none>" {
            return "<none>:\(tag)"
        }
        return "\(repository):\(tag)"
    }

    var sizeDisplay: String {
        let mb = Double(sizeBytes) / 1_000_000.0
        if mb >= 1000.0 {
            return String(format: "%.2f GB", mb / 1000.0)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.1f KB", Double(sizeBytes) / 1000.0)
        }
    }

    var createdAgo: String {
        relativeTime(from: createdAt)
    }

    static let rootfsMountPathLabelKeys = [
        "arcbox.rootfs.mount.path",
        "com.arcbox.rootfs.mount.path",
        "arcbox.image.rootfs.mount.path",
        "com.arcbox.image.rootfs.mount.path",
        "arcbox.rootfs.path",
        "com.arcbox.rootfs.path",
        "rootfs.mount.path",
    ]

    static func inferRootFSMountPath(
        explicitPath: String?,
        labels: [String: String]
    ) -> String? {
        if let explicitPath = normalizedPath(explicitPath) {
            return explicitPath
        }

        for key in rootfsMountPathLabelKeys {
            if let labelPath = normalizedPath(labels[key]) {
                return labelPath
            }
        }

        return nil
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/") else { return nil }
        return trimmed
    }
}

/// Calculate total and unused image sizes
func calculateImageStats(_ images: [ImageViewModel]) -> (totalSize: UInt64, unusedSize: UInt64, totalCount: Int, unusedCount: Int) {
    let totalSize = images.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    let unused = images.filter { !$0.inUse }
    let unusedSize = unused.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    return (totalSize, unusedSize, images.count, unused.count)
}
