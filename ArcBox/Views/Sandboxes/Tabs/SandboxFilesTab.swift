import AppKit
import ArcBoxClient
import SwiftUI
import UniformTypeIdentifiers

/// A completed or failed file transfer shown in the session history list.
private struct FileTransferRecord: Identifiable {
    enum Direction {
        case download
        case upload
    }

    let id = UUID()
    let direction: Direction
    let path: String
    let detail: String
    let succeeded: Bool
}

/// Files tab: path-based upload/download over the ReadFile/WriteFile RPCs.
///
/// sandbox.v1 has no directory-listing RPC, so this is a transfer surface,
/// not a browser; a tree view needs a future ListDir API.
struct SandboxFilesTab: View {
    let sandbox: SandboxViewModel

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    @State private var path = ""
    @State private var isTransferring = false
    @State private var transfers: [FileTransferRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)

            TextField(
                "Absolute path in sandbox", text: $path,
                prompt: Text("/etc/os-release")
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))

            Button("Download", action: download)
                .disabled(!canTransfer)
                .help("Read the file at this path and save it locally")

            Button("Upload…", action: upload)
                .disabled(!canTransfer)
                .help("Pick a local file and write it to this path")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if transfers.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textMuted)
                Text("Transfer files to and from the sandbox by absolute path.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Limited to 256 MiB per file. Directory browsing is not available in sandbox.v1.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(transfers.reversed()) { record in
                        transferRow(record)
                        Divider()
                    }
                }
            }
        }
    }

    private func transferRow(_ record: FileTransferRecord) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName: record.direction == .download
                    ? "arrow.down.circle" : "arrow.up.circle"
            )
            .foregroundStyle(record.succeeded ? AppColors.running : AppColors.error)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canTransfer: Bool {
        !isTransferring && client != nil
            && path.trimmingCharacters(in: .whitespaces).hasPrefix("/")
    }

    private func download() {
        guard let client else { return }
        let remotePath = path.trimmingCharacters(in: .whitespaces)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = (remotePath as NSString).lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isTransferring = true
        Task {
            defer { isTransferring = false }
            do {
                let data = try await vm.readFile(
                    sandboxID: sandbox.id, path: remotePath, client: client)
                try data.write(to: destination)
                record(.download, remotePath, "Saved \(byteCount(data.count)) to \(destination.path)", true)
            } catch {
                let message = vm.reportError(error, operation: "read_file", surface: false)
                record(.download, remotePath, message, false)
            }
        }
    }

    private func upload() {
        guard let client else { return }
        let remotePath = path.trimmingCharacters(in: .whitespaces)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }

        // Uploading onto a path that ends with "/" targets the directory:
        // append the local file name.
        let target =
            remotePath.hasSuffix("/")
            ? remotePath + source.lastPathComponent
            : remotePath

        isTransferring = true
        Task {
            defer { isTransferring = false }
            do {
                let data = try Data(contentsOf: source)
                try await vm.writeFile(
                    sandboxID: sandbox.id, path: target, data: data, client: client)
                record(.upload, target, "Wrote \(byteCount(data.count)) from \(source.path)", true)
            } catch {
                let message = vm.reportError(error, operation: "write_file", surface: false)
                record(.upload, target, message, false)
            }
        }
    }

    private func record(
        _ direction: FileTransferRecord.Direction,
        _ recordPath: String,
        _ detail: String,
        _ succeeded: Bool
    ) {
        transfers.append(
            FileTransferRecord(
                direction: direction, path: recordPath, detail: detail, succeeded: succeeded))
    }

    private func byteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
