import SwiftUI

/// Detail tab for volumes
enum VolumeDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case files = "Files"

    var id: String { rawValue }
}

/// Volume list state
@Observable
class VolumesViewModel {
    var volumes: [VolumeViewModel] = []
    var selectedID: String? = nil
    var activeTab: VolumeDetailTab = .info
    var listWidth: CGFloat = 380

    var totalSize: String {
        let bytes: UInt64 = volumes.compactMap(\.sizeBytes).reduce(0, +)
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.2f GB total", gb)
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.0f MB total", mb)
    }

    var selectedVolume: VolumeViewModel? {
        guard let id = selectedID else { return nil }
        return volumes.first { $0.id == id }
    }

    func selectVolume(_ id: String) {
        selectedID = id
    }

    func loadSampleData() {
        volumes = SampleData.volumes
    }
}
