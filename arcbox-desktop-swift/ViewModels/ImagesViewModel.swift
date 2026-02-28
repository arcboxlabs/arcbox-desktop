import SwiftUI
import DockerClient

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
        images.sorted { a, b in
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
            print("[ImagesVM] No docker client available")
            return
        }

        do {
            let response = try await docker.api.ImageList(.init())
            let imageList = try response.ok.body.json
            images = imageList.flatMap { ImageViewModel.fromDocker($0) }
            print("[ImagesVM] Loaded \(images.count) images")
        } catch {
            print("[ImagesVM] Error loading images: \(error)")
        }
    }

    func removeImage(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        if selectedID == id { selectedID = nil }
        do {
            let response = try await docker.api.ImageDelete(path: .init(name: id), query: .init(force: true))
            _ = try response.ok
            print("[ImagesVM] Successfully removed image \(id)")
        } catch {
            print("[ImagesVM] Error removing image \(id): \(error)")
        }
        await loadImages(docker: docker)
    }

    func loadSampleData() {
        images = SampleData.images
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
