import AppKit
import ArcBoxClient
import SwiftUI
import os

/// Files tab backed by an already-mounted local rootfs directory.
struct ContainerFilesTab: View {
    let container: ContainerViewModel

    @Environment(\.arcboxClient) private var arcboxClient

    @State private var selectedPath: String?
    @State private var stack = LayerStack()
    @State private var errorMessage: String?
    @State private var isLoadingRoot = false
    @State private var refreshToken = UUID()
    @State private var showHiddenFiles = LocalRootFSService.finderDefaultShowHiddenFiles()

    private var outlineReloadID: String {
        // Client availability is part of the key: the environment client is
        // nil during app startup, and the daemon-side resolution must re-run
        // once it is injected — `.task(id:)` only restarts on an id change.
        "\(container.id)|\(container.resolvedRootFSMountPath ?? "")|\(arcboxClient != nil)|\(showHiddenFiles)|\(refreshToken.uuidString)"
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
        .task(id: outlineReloadID) {
            await resolveRootPath(requestID: outlineReloadID)
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
            errorState("Container has no configured rootfs mount path.")
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

            Text(
                "Container filesystems are browsed through the read-only ~/ArcBox export, "
                    + "merging the container's writable layer over the image layers below it."
            )
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
        guard requestID == outlineReloadID, !Task.isCancelled else { return }
        errorMessage = nil
        isLoadingRoot = true
        selectedPath = nil
        stack = LayerStack()
        defer {
            if requestID == outlineReloadID, !Task.isCancelled {
                isLoadingRoot = false
            }
        }

        // Inspect-provided path (classic graph drivers) is already a merged
        // rootfs; under the containerd image store inspect carries no paths,
        // so the daemon resolves the layer stack and the tab merges it.
        let guestPaths: [String]
        if let mountPath = container.resolvedRootFSMountPath {
            guestPaths = [mountPath]
        } else {
            let resolution = await resolveViaDaemon()
            guard requestID == outlineReloadID, !Task.isCancelled else { return }
            switch resolution {
            case .resolved(let paths):
                guestPaths = paths
            case .failed(let message):
                errorMessage = message
                return
            case .cancelled:
                return
            }
        }

        let resolvedStack = await LayerStack.resolve(guestPaths: guestPaths)
        guard requestID == outlineReloadID, !Task.isCancelled else { return }
        stack = resolvedStack
        guard stack.rootURL != nil else {
            errorMessage = Self.unresolvedMessage(guestPaths: guestPaths)
            return
        }
        // Listings report further exclusions as they happen — a layer can
        // die after this point — and the badge unions them.
    }

    private static func unresolvedMessage(guestPaths: [String]) -> String {
        switch LayerStack.unresolved(guestPaths: guestPaths) {
        case .noPaths:
            return "Container has no resolvable filesystem path."
        case .outsideExport:
            return "Container filesystem path is outside the guest data root."
        case .exportUnavailable:
            return GuestDataMount.unavailableMessage(subject: "This container's filesystem")
        }
    }

    /// Resolves the container's snapshot layer stack via the daemon.
    ///
    /// Under the containerd image store the layer directories live in
    /// containerd's snapshotter, so the daemon queries the guest and returns
    /// guest paths: the writable (upper) layer the container wrote, followed
    /// by the image layers below it — overlay precedence order.
    private func resolveViaDaemon() async -> FilesTabPathResolution {
        guard let arcboxClient else {
            return .failed("ArcBox daemon is unavailable.")
        }
        var request = Arcbox_V1_ResolveContainerFsRequest()
        request.containerID = container.id
        return await FilesTabPathResolution.resolve(
            subject: "container",
            operation: {
                let response = try await arcboxClient.system.resolveContainerFs(
                    request, options: ArcBoxClient.defaultCallOptions)
                var paths: [String] = []
                if !response.upperDir.isEmpty {
                    paths.append(response.upperDir)
                }
                paths.append(contentsOf: response.lowerDirs.filter { !$0.isEmpty })
                return paths
            },
            onFailure: { error in
                Log.daemon.error(
                    "Failed to resolve container fs: \(error.localizedDescription, privacy: .private)")
            }
        )
    }

    private func revealSelectedInFinder() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
