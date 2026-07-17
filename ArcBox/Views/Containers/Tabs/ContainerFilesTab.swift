import AppKit
import ArcBoxClient
import SwiftUI
import os

/// Files tab backed by an already-mounted local rootfs directory.
struct ContainerFilesTab: View {
    let container: ContainerViewModel

    @Environment(\.arcboxClient) private var arcboxClient

    @State private var selectedPath: String?
    @State private var rootURL: URL?
    @State private var errorMessage: String?
    @State private var isLoadingRoot = false
    @State private var refreshToken = UUID()
    @State private var showHiddenFiles = LocalRootFSService.finderDefaultShowHiddenFiles()

    private var outlineReloadID: String {
        "\(container.id)|\(container.resolvedRootFSMountPath ?? "")|\(showHiddenFiles)|\(refreshToken.uuidString)"
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
            await resolveRootPath()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)

            Text(rootURL?.path ?? container.resolvedRootFSMountPath ?? "No rootfs mount path")
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
                "Container filesystems are browsed through the read-only ~/ArcBox export. The view shows the container's own writable layer; image layers stay in their own snapshots."
            )
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

        // Inspect-provided path (classic graph drivers), else ask the daemon
        // to resolve the container's snapshot layers (containerd image store,
        // where inspect carries no GraphDriver paths).
        var guestPath = container.resolvedRootFSMountPath
        if guestPath == nil {
            guestPath = await resolveViaDaemon()
        }

        // The resolved path is a guest path; browse it through the ~/ArcBox export.
        guard let guestPath,
            let hostURL = GuestDataMount.hostURL(forGuestPath: guestPath)
        else {
            rootURL = nil
            errorMessage =
                guestPath == nil
                ? "Container has no resolvable filesystem path."
                : "Container filesystem path is outside the guest data root."
            isLoadingRoot = false
            return
        }

        do {
            rootURL = try LocalRootFSService.resolveRootURL(path: hostURL.path)
        } catch {
            rootURL = nil
            errorMessage = GuestDataMount.unavailableMessage(subject: "This container's filesystem")
        }

        isLoadingRoot = false
    }

    /// Resolves the container's writable snapshot layer via the daemon.
    ///
    /// Under the containerd image store the layer directories live in
    /// containerd's snapshotter, so the daemon queries the guest and returns
    /// guest paths; the writable (upper) layer holds everything the container
    /// itself wrote.
    private func resolveViaDaemon() async -> String? {
        guard let arcboxClient else { return nil }
        var request = Arcbox_V1_ResolveContainerFsRequest()
        request.containerID = container.id
        do {
            let response = try await arcboxClient.system.resolveContainerFs(
                request, options: ArcBoxClient.defaultCallOptions)
            return response.upperDir.isEmpty ? nil : response.upperDir
        } catch {
            Log.daemon.error(
                "Failed to resolve container fs: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func revealSelectedInFinder() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
