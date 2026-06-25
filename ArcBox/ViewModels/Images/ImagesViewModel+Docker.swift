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

        do {
            let imageList = try await Perf.measure("image.list") {
                let response = try await docker.api.ImageList(.init())
                return try response.ok.body.json
            }
            var viewModels = imageList.flatMap { ImageViewModel.fromDocker($0) }
            applyCachedIcons(to: &viewModels)
            images = viewModels
            Log.image.info("Loaded \(self.images.count, privacy: .public) images")
            await fetchIcons(client: iconClient)
        } catch {
            Log.image.error("Error loading images: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .image, operation: "list")
        }
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
        guard let docker else { return false }
        let parsed = parseImageReference(reference)

        do {
            let response = try await docker.api.ImageCreate(
                query: .init(fromImage: parsed.fromImage, tag: parsed.tag, platform: platform)
            )
            _ = try response.ok
            Log.image.info("Pulled image \(reference, privacy: .private)")
            await loadImages(docker: docker)
            return true
        } catch {
            Log.image.error(
                "Error pulling image \(reference, privacy: .private): \(String(describing: error), privacy: .private)")
            ErrorReporting.capture(error, domain: .image, operation: "pull")
            return false
        }
    }

    /// Import an image from a local tar archive (equivalent to `docker load`). Returns true on success.
    func importImage(tarURL: URL, docker: DockerClient?) async -> Bool {
        guard let docker else { return false }
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
            return false
        }
    }

    func removeImage(_ id: String, dockerId: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else { return }
        if selectedID == id { selectedID = nil }

        do {
            let response = try await docker.api.ImageDelete(path: .init(name: dockerId), query: .init(force: true))
            _ = try response.ok
            Log.image.info("Removed image \(dockerId, privacy: .private)")
        } catch {
            Log.image.error(
                "Error removing image \(dockerId, privacy: .private): \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .image, operation: "remove")
            lastError = error.localizedDescription
        }
        await loadImages(docker: docker)
    }
}
