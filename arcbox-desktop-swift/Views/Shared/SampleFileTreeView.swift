import SwiftUI

/// Shared sample-file tree model used by placeholder tabs.
struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let isFolder: Bool
    let dateModified: String
    let size: String?
    let kind: String
    var children: [FileNode] = []
}

/// Shared sample-file tree row used by image/volume placeholder tabs.
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
                HStack(spacing: 4) {
                    if node.isFolder {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }

                    Image(systemName: node.isFolder ? "folder.fill" : "doc.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(node.isFolder ? Color.blue : AppColors.textSecondary)

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

            if node.isFolder && isExpanded {
                ForEach(node.children) { child in
                    FileRowView(node: child, depth: depth + 1, expandedFolders: $expandedFolders)
                }
            }
        }
    }
}
