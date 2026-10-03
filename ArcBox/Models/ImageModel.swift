import Foundation

/// Image view model for UI display
struct ImageViewModel: Identifiable, Hashable {
    let id: String
    /// Raw Docker image ID (sha256:…) for API calls
    let dockerId: String
    let repository: String
    let tag: String
    let sizeBytes: UInt64
    let createdAt: Date?
    let inUse: Bool
    let os: String
    let architecture: String
    var iconURL: String?

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
        guard let createdAt, createdAt.timeIntervalSince1970 > 0 else { return "Unknown" }
        return relativeTime(from: createdAt)
    }

    var platformDisplay: String? {
        let components = [os, architecture].compactMap { value in
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }

    var canDelete: Bool {
        !inUse
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
