import DockerClient
import Foundation

// MARK: - Docker API → UI Model Conversion

extension VolumeViewModel {
    /// Create a VolumeViewModel from a Docker Engine API Volume.
    init(fromDocker volume: Components.Schemas.Volume) {
        let createdAt = parseISO8601Date(volume.CreatedAt)

        let sizeBytes: UInt64?
        if let size = volume.UsageData?.Size, size >= 0 {
            sizeBytes = UInt64(size)
        } else {
            sizeBytes = nil
        }

        let inUse: Bool
        if let refCount = volume.UsageData?.RefCount, refCount > 0 {
            inUse = true
        } else {
            inUse = false
        }

        self.init(
            name: volume.Name,
            driver: volume.Driver,
            mountPoint: volume.Mountpoint,
            sizeBytes: sizeBytes,
            createdAt: createdAt,
            inUse: inUse,
            containerNames: []
        )
    }
}
