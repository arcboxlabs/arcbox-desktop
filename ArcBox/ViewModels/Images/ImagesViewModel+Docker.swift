import ArcBoxClient
import DockerClient
import Foundation
import OSLog
import OpenAPIRuntime

extension ImagesViewModel {
    /// Fetch icon URLs for all unique image repositories that are not already cached.
    func fetchIcons(client: ArcBoxClient?) async {
        guard let client else { return }
        let uncached = Set(images.map(\.repository))
            .filter { $0 != "<none>" }
            .subtracting(iconsByImage.keys)
        guard !uncached.isEmpty else { return }

        await withTaskGroup(of: (String, String?, Bool).self) { group in
            for repo in uncached {
                group.addTask {
                    do {
                        var request = Arcbox_V1_GetImageIconRequest()
                        request.fqin = repo
                        let response = try await client.icons.getImageIcon(
                            request, options: ArcBoxClient.defaultCallOptions)
                        let url = response.url.isEmpty ? nil : response.url
                        return (repo, url, true)
                    } catch {
                        Log.image.debug(
                            "Icon fetch failed for \(repo, privacy: .private): \(error.localizedDescription, privacy: .private)"
                        )
                        return (repo, nil, false)
                    }
                }
            }
            for await (repo, url, succeeded) in group {
                if let url {
                    iconsByImage[repo] = url
                } else if succeeded {
                    iconsByImage[repo] = ""
                }
            }
        }

        var snapshot = images
        applyCachedIcons(to: &snapshot)
        images = snapshot
    }

    /// Load images from Docker Engine API.
    func loadImages(docker: DockerClient?, iconClient: ArcBoxClient? = nil) async {
        guard let docker else {
            Log.image.debug("No docker client available")
            return
        }

        await listLoadGate.run {
            await self.performLoadImages(docker: docker, iconClient: iconClient)
        }
    }

    private func performLoadImages(
        docker: DockerClient,
        iconClient: ArcBoxClient?
    ) async {
        let isRefresh = loadState.beginLoading()
        do {
            let imageList = try await Perf.measure("image.list") {
                let response = try await docker.api.SystemDataUsage(
                    query: .init(_type: [.image])
                )
                return try response.ok.body.json.Images ?? []
            }
            let metadataByID = try await Self.inspectImageMetadata(
                imageIDs: imageList.map(\.Id)
            ) { id in
                try await docker.inspectImageSnapshot(id: id)
            }
            var viewModels = imageList.flatMap { image in
                let metadata = metadataByID[image.Id]
                return ImageViewModel.fromDocker(
                    image,
                    os: metadata?.os ?? "",
                    architecture: metadata?.architecture ?? ""
                )
            }
            applyCachedIcons(to: &viewModels)
            images = viewModels
            Log.image.info("Loaded \(self.images.count, privacy: .public) images")
            await fetchIcons(client: iconClient)
            loadState = .loaded
            refreshError = nil
            lastSuccessfulListLoad = ContinuousClock().now
        } catch {
            if loadState.cancelLoading(for: error, retainingLoadedContent: isRefresh) {
                return
            }
            Log.image.error("Error loading images: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .image, operation: "list")
            refreshError = loadState.fail(
                error.localizedDescription,
                retainingLoadedContent: isRefresh
            )
        }
    }

    static func inspectImageMetadata(
        imageIDs: [String],
        inspect: (String) async throws -> ImageInspectSnapshot
    ) async throws -> [String: ImageInspectSnapshot] {
        var metadataByID: [String: ImageInspectSnapshot] = [:]
        for id in imageIDs {
            do {
                let metadata = try await inspect(id)
                try Task.checkCancellation()
                metadataByID[id] = metadata
            } catch {
                if Task.isCancelled || error is CancellationError { throw error }
                Log.image.debug(
                    "Image metadata inspection failed for \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        return metadataByID
    }

    /// Parse an image reference into (fromImage, tag), handling registry ports and digests.
    /// e.g. "localhost:5000/repo:tag" → ("localhost:5000/repo", "tag")
    ///      "repo@sha256:abc" → ("repo@sha256:abc", nil)
    ///      "nginx:latest" → ("nginx", "latest")
    func parseImageReference(_ reference: String) -> (fromImage: String, tag: String?) {
        if reference.contains("@") {
            return (fromImage: reference, tag: nil)
        }
        // Only treat a colon after the last "/" as a tag separator
        let searchStart: String.Index
        if let lastSlash = reference.lastIndex(of: "/") {
            searchStart = reference.index(after: lastSlash)
        } else {
            searchStart = reference.startIndex
        }
        if let colonIndex = reference[searchStart...].lastIndex(of: ":") {
            let fromImage = String(reference[..<colonIndex])
            let tag = String(reference[reference.index(after: colonIndex)...])
            return (fromImage: fromImage, tag: tag.isEmpty ? nil : tag)
        }
        return (fromImage: reference, tag: nil)
    }

    /// Pull an image from a registry. Returns true on success.
    func pullImage(_ reference: String, platform: String?, docker: DockerClient?) async -> Bool {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return false
        }
        let parsed = parseImageReference(reference)
        let startedAt = CFAbsoluteTimeGetCurrent()

        do {
            let response = try await docker.api.ImageCreate(
                query: .init(fromImage: parsed.fromImage, tag: parsed.tag, platform: platform)
            )
            _ = try response.ok
            Log.image.info("Pulled image \(reference, privacy: .private)")
            Analytics.capture(
                .imagePulled,
                properties: [
                    "duration_ms": Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000),
                    "has_tag": parsed.tag != nil,
                    "explicit_platform": platform != nil,
                ])
            await loadImages(docker: docker)
            return true
        } catch {
            Log.image.error(
                "Error pulling image \(reference, privacy: .private): \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .image, operation: "pull")
            lastError = error.localizedDescription
            return false
        }
    }

    /// Import an image from a local tar archive (equivalent to `docker load`). Returns true on success.
    func importImage(tarURL: URL, docker: DockerClient?) async -> Bool {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return false
        }
        do {
            let data = try Data(contentsOf: tarURL, options: .mappedIfSafe)
            let response = try await docker.api.ImageLoad(
                body: .application_x_hyphen_tar(HTTPBody(data))
            )
            _ = try response.ok
            Log.image.info("Imported image from \(tarURL.lastPathComponent, privacy: .private)")
            await loadImages(docker: docker)
            return true
        } catch {
            Log.image.error("Error importing image: \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .image, operation: "import")
            lastError = error.localizedDescription
            return false
        }
    }

    func removeImage(_ id: String, dockerId: String, docker: DockerClient?) async {
        lastError = nil
        guard let image = images.first(where: { $0.id == id }) else { return }
        guard image.canDelete else {
            lastError = "Image is in use and cannot be deleted."
            return
        }
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }

        do {
            let response = try await docker.api.ImageDelete(path: .init(name: dockerId), query: .init(force: true))
            if applyImageDeletion(response, id: id) {
                Log.image.info("Removed image \(dockerId, privacy: .private)")
                Analytics.capture(.imageRemoved)
            }
        } catch {
            Log.image.error(
                "Error removing image \(dockerId, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .image, operation: "remove")
            lastError = error.localizedDescription
        }
        await loadImages(docker: docker)
    }

    @discardableResult
    func applyImageDeletion(_ response: Operations.ImageDelete.Output, id: String) -> Bool {
        if let message = response.deleteFailureMessage {
            lastError = message
            return false
        }
        if selectedID == id { selectedID = nil }
        return true
    }
}

extension Operations.ImageDelete.Output {
    nonisolated var deleteFailureMessage: String? {
        switch self {
        case .ok:
            nil
        case .notFound(let response):
            (try? response.body.json.message) ?? "Image not found."
        case .conflict(let response):
            (try? response.body.json.message) ?? "Docker cannot remove an image that is in use."
        case .internalServerError(let response):
            (try? response.body.json.message) ?? "Docker failed to remove the image."
        case .undocumented(let statusCode, _):
            "Unexpected response status \(statusCode)."
        }
    }
}
