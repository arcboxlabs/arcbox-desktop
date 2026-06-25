import DockerClient
import Foundation

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
