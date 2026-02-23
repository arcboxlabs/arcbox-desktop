import SwiftUI

/// Files tab showing container filesystem browser
struct ContainerFilesTab: View {
    let container: ContainerViewModel

    @State private var fileTree: [FileNode] = []
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("Name")
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 28)

                Text("Date Modified")
                    .frame(width: 180, alignment: .leading)
                Text("Size")
                    .frame(width: 80, alignment: .trailing)
                Text("Kind")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.surfaceElevated)

            Divider()

            // File list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(fileTree) { node in
                        FileRowView(
                            node: node,
                            depth: 0,
                            expandedFolders: $expandedFolders
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .onAppear {
            loadSampleFileTree()
        }
    }

    private func loadSampleFileTree() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy 'at' h:mm"

        fileTree = [
            FileNode(
                name: ".dockerenv", isFolder: false,
                dateModified: "Feb 23, 2026 at 16:20",
                size: "Zero kB", kind: "File"),
            FileNode(
                name: "bin", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "dev", isFolder: true,
                dateModified: "Feb 23, 2026 at 16:20",
                size: nil, kind: "Folder"),
            FileNode(
                name: "docker-entrypoint.d", isFolder: true,
                dateModified: "Dec 14, 2022 at 8:50",
                size: nil, kind: "Folder"),
            FileNode(
                name: "docker-entrypoint.sh", isFolder: false,
                dateModified: "Dec 14, 2022 at 8:50",
                size: "2 kB", kind: "File"),
            FileNode(
                name: "etc", isFolder: true,
                dateModified: "Feb 23, 2026 at 16:20",
                size: nil, kind: "Folder",
                children: [
                    FileNode(
                        name: "nginx", isFolder: true,
                        dateModified: "Dec 14, 2022 at 8:50",
                        size: nil, kind: "Folder"),
                    FileNode(
                        name: "hostname", isFolder: false,
                        dateModified: "Feb 23, 2026 at 16:20",
                        size: "1 kB", kind: "File"),
                    FileNode(
                        name: "hosts", isFolder: false,
                        dateModified: "Feb 23, 2026 at 16:20",
                        size: "1 kB", kind: "File"),
                    FileNode(
                        name: "resolv.conf", isFolder: false,
                        dateModified: "Feb 23, 2026 at 16:20",
                        size: "1 kB", kind: "File"),
                ]),
            FileNode(
                name: "home", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "lib", isFolder: true,
                dateModified: "Dec 14, 2022 at 8:50",
                size: nil, kind: "Folder"),
            FileNode(
                name: "media", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "mnt", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "opt", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "proc", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "root", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "run", isFolder: true,
                dateModified: "Feb 23, 2026 at 16:20",
                size: nil, kind: "Folder"),
            FileNode(
                name: "sbin", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "srv", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "sys", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "tmp", isFolder: true,
                dateModified: "Dec 14, 2022 at 8:50",
                size: nil, kind: "Folder"),
            FileNode(
                name: "usr", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "var", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
        ]
    }
}

// MARK: - File Node Model

struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let isFolder: Bool
    let dateModified: String
    let size: String?
    let kind: String
    var children: [FileNode] = []
}

// MARK: - File Row View

struct FileRowView: View {
    let node: FileNode
    let depth: Int
    @Binding var expandedFolders: Set<String>

    private var isExpanded: Bool {
        expandedFolders.contains(node.id.uuidString)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Indentation + disclosure triangle + icon + name
                HStack(spacing: 4) {
                    // Disclosure triangle for folders
                    if node.isFolder {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 12)
                    } else {
                        Spacer()
                            .frame(width: 12)
                    }

                    // File/folder icon
                    Image(
                        systemName: node.isFolder
                            ? "folder.fill" : "doc.fill"
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(
                        node.isFolder ? Color.blue : AppColors.textSecondary)

                    Text(node.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .padding(.leading, CGFloat(depth) * 20 + 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(node.dateModified)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 180, alignment: .leading)

                Text(node.size ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 80, alignment: .trailing)

                Text(node.kind)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isFolder {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isExpanded {
                            expandedFolders.remove(node.id.uuidString)
                        } else {
                            expandedFolders.insert(node.id.uuidString)
                        }
                    }
                }
            }

            Divider().opacity(0.2)

            // Children (if expanded)
            if node.isFolder && isExpanded {
                ForEach(node.children) { child in
                    FileRowView(
                        node: child,
                        depth: depth + 1,
                        expandedFolders: $expandedFolders
                    )
                }
            }
        }
    }
}
