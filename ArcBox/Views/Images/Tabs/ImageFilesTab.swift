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

        var errorDescription: String? {
            switch self {
            case .dockerUnavailable:
                return "Docker client is unavailable."
            case .missingRootPath:
                return "Image has no resolvable filesystem path."
            case .inspectFailed(let reason):
                return "Failed to inspect image: \(reason)"
            }
        }
    }

    let image: ImageViewModel
    @Environment(\.dockerClient) private var docker
    @Environment(\.arcboxClient) private var arcboxClient

    @State private var selectedPath: String?
    @State private var rootURL: URL?
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
            await resolveRootPath()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)

            Text(rootURL?.path ?? resolvedRootFSMountPath ?? "No rootfs mount path")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

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
        } else if let rootURL {
            LocalRootFSOutlineView(
                rootURL: rootURL,
                showHiddenFiles: showHiddenFiles,
                reloadID: outlineReloadID,
                selectedPath: $selectedPath,
                onOpenURL: { url in
                    _ = NSWorkspace.shared.open(url)
                }
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

            Button("Refresh") {
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

    private func resolveRootPath() async {
        errorMessage = nil
        isLoadingRoot = true
        selectedPath = nil
        rootURL = nil

        do {
            // The layer directory is a guest path; browse it via ~/ArcBox.
            let mountPoint = try await resolveImageRootFSMountPath()
            resolvedRootFSMountPath = mountPoint
            guard let hostURL = GuestDataMount.hostURL(forGuestPath: mountPoint) else {
                errorMessage = "Image layer path is outside the guest data root."
                isLoadingRoot = false
                return
            }
            rootURL = try LocalRootFSService.resolveRootURL(path: hostURL.path)
        } catch let error as ImageFilesTabError {
            resolvedRootFSMountPath = nil
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = GuestDataMount.unavailableMessage(subject: "This image's layers")
        }

        isLoadingRoot = false
    }

    private func resolveImageRootFSMountPath() async throws -> String {
        guard let docker else {
            throw ImageFilesTabError.dockerUnavailable
        }

        do {
            let snapshot = try await docker.inspectImageSnapshot(id: image.dockerId)
            if let resolvedPath = ImageViewModel.inferRootFSMountPath(
                explicitPath: snapshot.rootfsMountPath,
                labels: snapshot.labels
            ) {
                return resolvedPath
            }
            // Containerd image store: inspect carries no layer paths; ask
            // the daemon to resolve the layer chain and browse the top
            // layer's directory.
            if let resolvedPath = await resolveViaDaemon(diffIDs: snapshot.rootfsLayers) {
                return resolvedPath
            }
            throw ImageFilesTabError.missingRootPath
        } catch let error as ImageFilesTabError {
            throw error
        } catch {
            throw ImageFilesTabError.inspectFailed(error.localizedDescription)
        }
    }

    /// Resolves the image's top layer directory via the daemon, keyed by
    /// the layer chain ID computed from the inspect diff IDs.
    private func resolveViaDaemon(diffIDs: [String]) async -> String? {
        guard let arcboxClient,
            let topChainID = ImageLayerChain.topChainID(diffIDs: diffIDs)
        else { return nil }
        var request = Arcbox_V1_ResolveImageFsRequest()
        request.topChainID = topChainID
        do {
            let response = try await arcboxClient.system.resolveImageFs(
                request, options: ArcBoxClient.defaultCallOptions)
            return response.lowerDirs.first
        } catch {
            Log.daemon.error(
                "Failed to resolve image fs: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func revealSelectedInFinder() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
