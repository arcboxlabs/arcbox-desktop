import SwiftUI

/// Files tab showing volume filesystem browser
struct VolumeFilesTab: View {
    let volume: VolumeViewModel

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
                name: "data", isFolder: true,
                dateModified: "Feb 20, 2026 at 14:30",
                size: nil, kind: "Folder",
                children: [
                    FileNode(
                        name: "base", isFolder: true,
                        dateModified: "Feb 18, 2026 at 10:15",
                        size: nil, kind: "Folder"),
                    FileNode(
                        name: "global", isFolder: true,
                        dateModified: "Feb 20, 2026 at 14:30",
                        size: nil, kind: "Folder"),
                    FileNode(
                        name: "pg_wal", isFolder: true,
                        dateModified: "Feb 23, 2026 at 8:00",
                        size: nil, kind: "Folder"),
                ]),
            FileNode(
                name: "backups", isFolder: true,
                dateModified: "Feb 22, 2026 at 3:00",
                size: nil, kind: "Folder",
                children: [
                    FileNode(
                        name: "daily_2026-02-22.sql.gz", isFolder: false,
                        dateModified: "Feb 22, 2026 at 3:00",
                        size: "48 MB", kind: "File"),
                    FileNode(
                        name: "daily_2026-02-21.sql.gz", isFolder: false,
                        dateModified: "Feb 21, 2026 at 3:00",
                        size: "47 MB", kind: "File"),
                ]),
            FileNode(
                name: "postgresql.conf", isFolder: false,
                dateModified: "Feb 15, 2026 at 9:22",
                size: "28 kB", kind: "File"),
            FileNode(
                name: "pg_hba.conf", isFolder: false,
                dateModified: "Feb 15, 2026 at 9:22",
                size: "5 kB", kind: "File"),
            FileNode(
                name: "pg_ident.conf", isFolder: false,
                dateModified: "Feb 15, 2026 at 9:22",
                size: "2 kB", kind: "File"),
            FileNode(
                name: "postmaster.pid", isFolder: false,
                dateModified: "Feb 23, 2026 at 8:00",
                size: "1 kB", kind: "File"),
            FileNode(
                name: "PG_VERSION", isFolder: false,
                dateModified: "Jan 24, 2026 at 12:00",
                size: "1 kB", kind: "File"),
        ]
    }
}
