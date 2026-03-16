import SwiftUI
import DockerClient
import OSLog

/// Detail tab for images
enum ImageDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case terminal = "Terminal"
    case files = "Files"

    var id: String { rawValue }
}

/// Sort field for images
enum ImageSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
    case size = "Size"
}

/// Image list state
@Observable
class ImagesViewModel {
    var images: [ImageViewModel] = []
    var selectedID: String? = nil
    var activeTab: ImageDetailTab = .info
    var listWidth: CGFloat = 320
    var showPullImageSheet: Bool = false
    var searchText: String = ""
    var isSearching: Bool = false
    var sortBy: ImageSortField = .name
    var sortAscending: Bool = true

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

    // MARK: - Docker API Operations

    /// Load images from Docker Engine API.
    func loadImages(docker: DockerClient?) async {
        guard let docker else {
            Log.image.debug("No docker client available")
            return
        }

        do {
            let response = try await docker.api.ImageList(.init())
            let imageList = try response.ok.body.json
            images = imageList.flatMap { ImageViewModel.fromDocker($0) }
            Log.image.info("Loaded \(self.images.count, privacy: .public) images")
        } catch {
            Log.image.error("Error loading images: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeImage(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        if selectedID == id { selectedID = nil }
        do {
            let response = try await docker.api.ImageDelete(path: .init(name: id), query: .init(force: true))
            _ = try response.ok
            Log.image.info("Removed image \(id, privacy: .public)")
        } catch {
            Log.image.error("Error removing image \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        await loadImages(docker: docker)
    }

}

// MARK: - Docker API → UI Model Conversion

extension ImageViewModel {
    /// Create ImageViewModels from a Docker Engine API ImageSummary.
    /// One ImageSummary can have multiple RepoTags, producing multiple view models.
    static func fromDocker(_ summary: Components.Schemas.ImageSummary) -> [ImageViewModel] {
        let tags = summary.RepoTags.isEmpty ? ["<none>:<none>"] : summary.RepoTags

        return tags.map { repoTag in
            let parts = repoTag.split(separator: ":", maxSplits: 1)
            let repository = parts.first.map(String.init) ?? "<none>"
            let tag = parts.count > 1 ? String(parts[1]) : "<none>"

            return ImageViewModel(
                id: summary.Id,
                repository: repository,
                tag: tag,
                sizeBytes: UInt64(summary.Size),
                createdAt: Date(timeIntervalSince1970: TimeInterval(summary.Created)),
                inUse: summary.Containers > 0,
                os: "",
                architecture: ""
            )
        }
    }
}
