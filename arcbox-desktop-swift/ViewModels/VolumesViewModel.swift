import SwiftUI
import DockerClient

/// Detail tab for volumes
enum VolumeDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case files = "Files"

    var id: String { rawValue }
}

/// Sort field for volumes
enum VolumeSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
    case size = "Size"
}

/// Volume list state
@Observable
class VolumesViewModel {
    var volumes: [VolumeViewModel] = []
    var selectedID: String? = nil
    var activeTab: VolumeDetailTab = .info
    var listWidth: CGFloat = 320
    var showNewVolumeSheet: Bool = false
    var sortBy: VolumeSortField = .name
    var sortAscending: Bool = true

    var totalSize: String {
        let bytes: UInt64 = volumes.compactMap(\.sizeBytes).reduce(0, +)
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.2f GB total", gb)
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.0f MB total", mb)
    }

    var sortedVolumes: [VolumeViewModel] {
        volumes.sorted { a, b in
            let result: Bool
            switch sortBy {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .dateCreated:
                result = a.createdAt < b.createdAt
            case .size:
                result = (a.sizeBytes ?? 0) < (b.sizeBytes ?? 0)
            }
            return sortAscending ? result : !result
        }
    }

    var selectedVolume: VolumeViewModel? {
        guard let id = selectedID else { return nil }
        return volumes.first { $0.id == id }
    }

    func selectVolume(_ id: String) {
        selectedID = id
    }

    // MARK: - Docker API Operations

    /// Load volumes from Docker Engine API.
    func loadVolumes(docker: DockerClient?) async {
        guard let docker else {
            print("[VolumesVM] No docker client available")
            return
        }

        do {
            let response = try await docker.api.VolumeList(.init())
            let volumeResponse = try response.ok.body.json
            volumes = (volumeResponse.Volumes ?? []).map { VolumeViewModel(fromDocker: $0) }
            print("[VolumesVM] Loaded \(volumes.count) volumes")
        } catch {
            print("[VolumesVM] Error loading volumes: \(error)")
        }
    }

    func removeVolume(_ name: String, docker: DockerClient?) async {
        guard let docker else { return }
        _ = try? await docker.api.VolumeDelete(path: .init(name: name))
        await loadVolumes(docker: docker)
    }

    func loadSampleData() {
        volumes = SampleData.volumes
    }
}

// MARK: - Docker API → UI Model Conversion

extension VolumeViewModel {
    /// Create a VolumeViewModel from a Docker Engine API Volume.
    init(fromDocker volume: Components.Schemas.Volume) {
        let createdAt: Date
        if let created = volume.CreatedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdAt = formatter.date(from: created) ?? Date()
        } else {
            createdAt = Date()
        }

        self.init(
            name: volume.Name,
            driver: volume.Driver,
            mountPoint: volume.Mountpoint,
            sizeBytes: nil,
            createdAt: createdAt,
            inUse: false,
            containerNames: []
        )
    }
}
