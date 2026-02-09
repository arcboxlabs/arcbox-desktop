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
            return String(format: "%.1f GB", mb / 1000.0)
        }
        return String(format: "%.0f MB", mb)
    }

    var createdAgo: String {
        relativeTime(from: createdAt)
    }
}

/// Calculate total and unused image sizes
func calculateImageStats(_ images: [ImageViewModel]) -> (totalSize: UInt64, unusedSize: UInt64, totalCount: Int, unusedCount: Int) {
    let totalSize = images.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    let unused = images.filter { !$0.inUse }
    let unusedSize = unused.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    return (totalSize, unusedSize, images.count, unused.count)
}
