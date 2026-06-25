import Foundation
import SwiftUI

/// Volume list state
@MainActor
@Observable
class VolumesViewModel {
    var volumes: [VolumeViewModel] = []
    var selectedID: String?
    var activeTab: VolumeDetailTab = .info
    var listWidth: CGFloat = 320
    var showNewVolumeSheet: Bool = false
    var searchText: String = ""
    var isSearching: Bool = false
    var sortBy: VolumeSortField = .name
    var sortAscending: Bool = true
    var lastError: String?

    var totalSize: String {
        let bytes: UInt64 = volumes.compactMap(\.sizeBytes).reduce(0, +)
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.2f GB total", gb)
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.1f MB total", mb)
    }

    var sortedVolumes: [VolumeViewModel] {
        let filtered: [VolumeViewModel]
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = volumes.filter {
                $0.name.lowercased().contains(query)
                    || $0.driver.lowercased().contains(query)
            }
        } else {
            filtered = volumes
        }
        return filtered.sorted { a, b in
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
}
