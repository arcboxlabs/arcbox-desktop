import SwiftUI
import ArcBoxClient
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
    private var iconsByImage: [String: String] = [:]

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

    private func applyCachedIcons(to viewModels: inout [ImageViewModel]) {
        for i in viewModels.indices {
            viewModels[i].iconURL = iconsByImage[viewModels[i].repository]
        }
    }

    /// Fetch icon URLs for all unique image repositories that are not already cached.
    func fetchIcons(client: ArcBoxClient?) async {
        guard let client else { return }
        let uncached = Set(images.map(\.repository))
            .filter { $0 != "<none>" }
            .subtracting(iconsByImage.keys)
        guard !uncached.isEmpty else { return }

        await withTaskGroup(of: (String, String?).self) { group in
            for repo in uncached {
                group.addTask {
                    do {
                        var request = Arcbox_V1_GetImageIconRequest()
                        request.fqin = repo
                        let response = try await client.icons.getImageIcon(request)
                        let url = response.url.isEmpty ? nil : response.url
                        return (repo, url)
                    } catch {
                        Log.image.debug("Icon fetch failed for \(repo, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return (repo, nil)
                    }
                }
            }
            for await (repo, url) in group {
                iconsByImage[repo] = url ?? ""
            }
        }

        var snapshot = images
        applyCachedIcons(to: &snapshot)
        images = snapshot
    }

    // MARK: - Docker API Operations

    /// Load images from Docker Engine API.
    func loadImages(docker: DockerClient?, iconClient: ArcBoxClient? = nil) async {
        guard let docker else {
            Log.image.debug("No docker client available")
            return
        }

        do {
            let response = try await docker.api.ImageList(.init())
            let imageList = try response.ok.body.json
            var viewModels = imageList.flatMap { ImageViewModel.fromDocker($0) }
            applyCachedIcons(to: &viewModels)
            images = viewModels
            Log.image.info("Loaded \(self.images.count, privacy: .public) images")
            await fetchIcons(client: iconClient)
        } catch {
            Log.image.error("Error loading images: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeImage(_ id: String, dockerId: String, docker: DockerClient?) async {
        guard let docker else { return }
        if selectedID == id { selectedID = nil }
        do {
            let response = try await docker.api.ImageDelete(path: .init(name: dockerId), query: .init(force: true))
            _ = try response.ok
            Log.image.info("Removed image \(dockerId, privacy: .public)")
        } catch {
            Log.image.error("Error removing image \(dockerId, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
                id: "\(summary.Id)/\(repository):\(tag)",
                dockerId: summary.Id,
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
