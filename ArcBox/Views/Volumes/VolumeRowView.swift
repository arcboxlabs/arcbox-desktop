import AppKit
import SwiftUI

/// Single volume row
struct VolumeRowView: View {
    let volume: VolumeViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Volume icon
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.iconBackground)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }

            // Name and size
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(volume.sizeDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.67) : AppColors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button
            if isHovered || isSelected {
                IconButton(
                    symbol: "trash.fill",
                    action: { showDeleteConfirm = true },
                    color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? AppColors.selection
                        : (isHovered ? AppColors.hover : Color.clear)
                )
        )
        .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.text)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(volume.name, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .confirmationDialog("Delete Volume", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete volume \"\(volume.name)\"? This action cannot be undone.")
        }
    }
}
