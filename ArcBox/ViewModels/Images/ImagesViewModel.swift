import Foundation
import SwiftUI

/// Image list state
@MainActor
@Observable
class ImagesViewModel {
    var images: [ImageViewModel] = []
    var selectedID: String?
    var activeTab: ImageDetailTab = .info
    var listWidth: CGFloat = 320
    var showPullImageSheet: Bool = false
    var searchText: String = ""
    var isSearching: Bool = false
    var sortBy: ImageSortField = .name
    var sortAscending: Bool = true
    var lastError: String?
    var iconsByImage: [String: String] = [:]

    var totalSize: String {
        let bytes: UInt64 = images.map(\.sizeBytes).reduce(0, +)
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.2f GB total", gb)
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.1f MB total", mb)
    }

    var sortedImages: [ImageViewModel] {
        let filtered: [ImageViewModel]
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = images.filter {
                $0.repository.lowercased().contains(query)
                    || $0.tag.lowercased().contains(query)
            }
        } else {
            filtered = images
        }
        return filtered.sorted { a, b in
            let result: Bool
            switch sortBy {
            case .name:
                result = a.repository.localizedCaseInsensitiveCompare(b.repository) == .orderedAscending
            case .dateCreated:
                result = a.createdAt < b.createdAt
            case .size:
                result = a.sizeBytes < b.sizeBytes
            }
            return sortAscending ? result : !result
        }
    }

    var selectedImage: ImageViewModel? {
        guard let id = selectedID else { return nil }
        return images.first { $0.id == id }
    }

    func selectImage(_ id: String) {
        selectedID = id
    }

    func applyCachedIcons(to viewModels: inout [ImageViewModel]) {
        for i in viewModels.indices {
            viewModels[i].iconURL = iconsByImage[viewModels[i].repository]
        }
    }
}
