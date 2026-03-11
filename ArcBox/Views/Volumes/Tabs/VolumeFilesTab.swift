import SwiftUI
import AppKit

/// Files tab showing volume filesystem browser
struct VolumeFilesTab: View {
    let volume: VolumeViewModel

    @State private var selectedPath: String?
    @State private var rootURL: URL?
    @State private var errorMessage: String?
    @State private var isLoadingRoot = false
    @State private var refreshToken = UUID()
    @State private var showHiddenFiles = LocalRootFSService.finderDefaultShowHiddenFiles()

    private let fileService = LocalRootFSService()

    private var outlineReloadID: String {
        "\(volume.id)|\(volume.mountPoint)|\(showHiddenFiles)|\(refreshToken.uuidString)"
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

            Text(rootURL?.path ?? volume.mountPoint)
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
            errorState("Volume has no mount point.")
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

            Text("Docker mount point: \(volume.mountPoint)")
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

        let mountPoint = volume.mountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mountPoint.isEmpty else {
            rootURL = nil
            errorMessage = "Volume has no mount point."
            isLoadingRoot = false
            return
        }

        do {
            rootURL = try fileService.resolveRootURL(path: mountPoint)
        } catch let error as LocalRootFSService.RootFSError {
            rootURL = nil
            switch error {
            case .missingRootPath:
                errorMessage = "Volume has no mount point."
            case .pathNotFound(let path):
                errorMessage = "Volume mount point does not exist: \(path)"
            case .notDirectory(let path):
                errorMessage = "Volume mount point is not a directory: \(path)"
            }
        } catch {
            rootURL = nil
            errorMessage = error.localizedDescription
        }

        isLoadingRoot = false
    }

    private func revealSelectedInFinder() {
        guard let url = selectedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
