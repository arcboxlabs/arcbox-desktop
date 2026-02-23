import SwiftUI

/// Files tab showing image layer filesystem browser
struct ImageFilesTab: View {
    let image: ImageViewModel

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
        fileTree = [
            FileNode(
                name: "bin", isFolder: true,
                dateModified: "Nov 22, 2022 at 21:08",
                size: nil, kind: "Folder"),
            FileNode(
                name: "dev", isFolder: true,
                dateModified: "Feb 23, 2026 at 16:20",
                size: nil, kind: "Folder"),
            FileNode(
                name: "etc", isFolder: true,
                dateModified: "Feb 23, 2026 at 16:20",
                size: nil, kind: "Folder",
                children: [
                    FileNode(
                        name: "apt", isFolder: true,
                        dateModified: "Nov 22, 2022 at 21:08",
                        size: nil, kind: "Folder"),
                    FileNode(
                        name: "hostname", isFolder: false,
                        dateModified: "Feb 23, 2026 at 16:20",
                        size: "1 kB", kind: "File"),
                    FileNode(
                        name: "passwd", isFolder: false,
                        dateModified: "Nov 22, 2022 at 21:08",
                        size: "2 kB", kind: "File"),
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
