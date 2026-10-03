import AppKit
import ArcBoxClient
import DockerClient
import SwiftUI
import os

/// Files tab showing image layer filesystem browser
struct ImageFilesTab: View {
    private enum ImageFilesTabError: LocalizedError {
        case dockerUnavailable
        case missingRootPath
        case inspectFailed(String)
        case resolutionFailed(String)

        var errorDescription: String? {
            switch self {
            case .dockerUnavailable:
                return "Docker client is unavailable."
            case .missingRootPath:
                return "Image has no resolvable filesystem path."
            case .inspectFailed(let reason):
                return "Failed to inspect image: \(reason)"
            case .resolutionFailed(let message):
                return message
            }
        }
    }

    let image: ImageViewModel
    @Environment(\.dockerClient) private var docker
    @Environment(\.arcboxClient) private var arcboxClient

    @State private var selectedPath: String?
    @State private var stack = LayerStack()
    @State private var resolvedRootFSMountPath: String?
    @State private var errorMessage: String?
    @State private var isLoadingRoot = false
    @State private var refreshToken = UUID()
    @State private var showHiddenFiles = LocalRootFSService.finderDefaultShowHiddenFiles()

    private var resolveTaskID: String {
        // Client availability is part of the key: the environment clients
        // are nil during app startup, and resolution must re-run once they
        // are injected — `.task(id:)` only restarts on an id change.
        "\(image.id)|\(docker != nil)|\(arcboxClient != nil)|\(refreshToken.uuidString)"
    }

    private var outlineReloadID: String {
        "\(image.id)|\(resolvedRootFSMountPath ?? "")|\(showHiddenFiles)|\(refreshToken.uuidString)"
    }

    private var selectedURL: URL? {
        guard let selectedPath else { return nil }
        return URL(fileURLWithPath: selectedPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(id: resolveTaskID) {
            await resolveRootPath(requestID: resolveTaskID)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)

            Text("/")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            LayerMergeBadge(stack: stack)

            Spacer()

            Button(
                action: { showHiddenFiles.toggle() },
                label: {
                    Image(systemName: showHiddenFiles ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                }
            )
            .buttonStyle(.plain)
            .help(showHiddenFiles ? "Hide hidden files" : "Show hidden files")

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button(action: revealSelectedInFinder) {
                Image(systemName: "finder")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(selectedURL == nil)
            .help("Reveal selected in Finder")
        }
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingRoot {
            VStack {
                Spacer()
                ProgressView("Loading files...")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        } else if let errorMessage {
            errorState(errorMessage)
        } else if let rootURL = stack.rootURL {
            LocalRootFSOutlineView(
                rootURL: rootURL,
                layers: stack.layers,
                displayRootPath: "/",
                showHiddenFiles: showHiddenFiles,
                reloadID: outlineReloadID,
                selectedPath: $selectedPath,
                onOpenURL: { url in
                    _ = NSWorkspace.shared.open(url)
                },
                onExcludedLayers: { stack.exclude($0) }
            )
        } else {
            errorState("Image has no configured rootfs mount path.")
        }
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.textMuted)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text("Image layers are browsed through the read-only ~/ArcBox export.")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(FilesTabPathResolution.retryTitle) {
                refresh()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() {
        refreshToken = UUID()
    }

    private func resolveRootPath(requestID: String) async {
        guard requestID == resolveTaskID, !Task.isCancelled else { return }
        errorMessage = nil
        isLoadingRoot = true
        selectedPath = nil
        stack = LayerStack()
        defer {
            if requestID == resolveTaskID, !Task.isCancelled {
                isLoadingRoot = false
            }
        }

        do {
            // The layer directories are guest paths; browse them via ~/ArcBox.
            let mountPoints = try await resolveImageLayerPaths()
            guard requestID == resolveTaskID, !Task.isCancelled else { return }
            resolvedRootFSMountPath = mountPoints.first

            let resolvedStack = await LayerStack.resolve(guestPaths: mountPoints)
            guard requestID == resolveTaskID, !Task.isCancelled else { return }
            stack = resolvedStack
            guard stack.rootURL != nil else {
                errorMessage = Self.unresolvedMessage(guestPaths: mountPoints)
                return
            }
            // Listings report further exclusions as they happen — a layer can
            // die after this point — and the badge unions them.
        } catch is CancellationError {
            return
        } catch let error as ImageFilesTabError {
            guard requestID == resolveTaskID, !Task.isCancelled else { return }
            resolvedRootFSMountPath = nil
            errorMessage = error.localizedDescription
        } catch {
            guard requestID == resolveTaskID, !Task.isCancelled else { return }
            errorMessage = GuestDataMount.unavailableMessage(subject: "This image's layers")
        }
    }

    private static func unresolvedMessage(guestPaths: [String]) -> String {
        switch LayerStack.unresolved(guestPaths: guestPaths) {
        case .noPaths, .outsideExport:
            return "Image layer path is outside the guest data root."
        case .exportUnavailable:
            return GuestDataMount.unavailableMessage(subject: "This image's layers")
        }
    }

    private func resolveImageLayerPaths() async throws -> [String] {
        guard let docker else {
            throw ImageFilesTabError.dockerUnavailable
        }

        do {
            let snapshot = try await docker.inspectImageSnapshot(id: image.dockerId)
            if let resolvedPath = ImageViewModel.inferRootFSMountPath(
                explicitPath: snapshot.rootfsMountPath,
                labels: snapshot.labels
            ) {
                return [resolvedPath]
            }
            // Containerd image store: inspect carries no layer paths; ask
            // the daemon to resolve the layer chain, then merge the layers
            // into the filesystem the image would present when run.
            switch await resolveViaDaemon(diffIDs: snapshot.rootfsLayers) {
            case .resolved(let paths) where !paths.isEmpty:
                return paths
            case .resolved:
                throw ImageFilesTabError.missingRootPath
            case .failed(let message):
                throw ImageFilesTabError.resolutionFailed(message)
            case .cancelled:
                throw CancellationError()
            }
        } catch let error as ImageFilesTabError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch {
            try Task.checkCancellation()
            Log.image.error(
                "Failed to inspect image: \(error.localizedDescription, privacy: .private)")
            throw ImageFilesTabError.inspectFailed(error.localizedDescription)
        }
    }

    /// Resolves the image's layer directories via the daemon, keyed by the
    /// layer chain ID computed from the inspect diff IDs. The daemon returns
    /// them in overlay precedence order, topmost layer first.
    private func resolveViaDaemon(diffIDs: [String]) async -> FilesTabPathResolution {
        guard let topChainID = ImageLayerChain.topChainID(diffIDs: diffIDs) else {
            return .resolved([])
        }
        guard let arcboxClient else {
            return .failed("ArcBox daemon is unavailable.")
        }
        var request = Arcbox_V1_ResolveImageFsRequest()
        request.topChainID = topChainID
        return await FilesTabPathResolution.resolve(
            subject: "image",
            operation: {
                let response = try await arcboxClient.system.resolveImageFs(
                    request, options: ArcBoxClient.defaultCallOptions)
                return response.lowerDirs.filter { !$0.isEmpty }
            },
            onFailure: { error in
                Log.daemon.error(
                    "Failed to resolve image fs: \(error.localizedDescription, privacy: .private)")
            }
        )
    }

    private func revealSelectedInFinder() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
