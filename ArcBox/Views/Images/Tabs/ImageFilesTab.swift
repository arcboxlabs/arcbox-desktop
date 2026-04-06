import AppKit
import DockerClient
import SwiftUI

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
                return "Image has no configured rootfs mount path."
            case .inspectFailed(let reason):
                return "Failed to inspect image: \(reason)"
            }
        }
    }

    let image: ImageViewModel
    @Environment(\.dockerClient) private var docker

    @State private var selectedPath: String?
    @State private var rootURL: URL?
    @State private var resolvedRootFSMountPath: String?
    @State private var errorMessage: String?
    @State private var isLoadingRoot = false
    @State private var refreshToken = UUID()
    @State private var showHiddenFiles = LocalRootFSService.finderDefaultShowHiddenFiles()

    private let fileService = LocalRootFSService()

    private var resolveTaskID: String {
        "\(image.id)|\(refreshToken.uuidString)"
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

            Button(action: { showHiddenFiles.toggle() }) {
                Image(systemName: showHiddenFiles ? "eye.slash" : "eye")
                    .font(.system(size: 12))
            }
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

            Text("Set rootfs path via image labels (for example: arcbox.rootfs.mount.path).")
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
            let mountPoint = try await resolveImageRootFSMountPath()
            resolvedRootFSMountPath = mountPoint
            rootURL = try fileService.resolveRootURL(path: mountPoint)
        } catch let error as ImageFilesTabError {
            resolvedRootFSMountPath = nil
            errorMessage = error.localizedDescription
        } catch let error as LocalRootFSService.RootFSError {
            resolvedRootFSMountPath = nil
            switch error {
            case .missingRootPath:
                errorMessage = "Image has no configured rootfs mount path."
            case .pathNotFound(let path):
                errorMessage = "Image rootfs path does not exist: \(path)"
            case .notDirectory(let path):
                errorMessage = "Image rootfs path is not a directory: \(path)"
            }
        } catch {
            resolvedRootFSMountPath = nil
            errorMessage = "Failed to load image filesystem: \(error.localizedDescription)"
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
            throw ImageFilesTabError.missingRootPath
        } catch let error as ImageFilesTabError {
            throw error
        } catch {
            throw ImageFilesTabError.inspectFailed(error.localizedDescription)
        }
    }

    private func revealSelectedInFinder() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
