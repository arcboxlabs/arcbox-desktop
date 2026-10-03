import Foundation
import Observation

/// Volume list state
@MainActor
@Observable
class VolumesViewModel {
    var volumes: [VolumeViewModel] = []
    var loadState: LoadPhase = .waiting
    var refreshError: String?
    var lastSuccessfulListLoad: ContinuousClock.Instant?
    let listLoadGate = SingleFlightLoadGate()
    var selectedID: String?
    var activeTab: VolumeDetailTab = .info
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
            let comparison: ComparisonResult
            switch sortBy {
            case .name:
                comparison = a.name.localizedCaseInsensitiveCompare(b.name)
            case .dateCreated:
                comparison = a.createdAt.compare(b.createdAt)
            case .size:
                let lhs = a.sizeBytes ?? 0
                let rhs = b.sizeBytes ?? 0
                comparison =
                    lhs == rhs
                    ? .orderedSame
                    : (lhs < rhs ? .orderedAscending : .orderedDescending)
            }
            if comparison == .orderedSame {
                return sortAscending ? a.id < b.id : a.id > b.id
            }
            return sortAscending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
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
