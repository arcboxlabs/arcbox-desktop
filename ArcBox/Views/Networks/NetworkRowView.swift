import AppKit
import SwiftUI

/// Single network row
struct NetworkRowView: View {
    let network: NetworkViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Network icon
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.iconBackground)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: network.isSystem ? "globe" : "link")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }

            // Name and driver
            VStack(alignment: .leading, spacing: 2) {
                Text(network.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(network.driverDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.67) : AppColors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button (only for non-system networks)
            if !network.isSystem && (isHovered || isSelected) {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(network.name), \(network.driverDisplay)")
        .onTapGesture(perform: onSelect)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(network.name, forType: .string)
            }
            if !network.isSystem {
                Divider()
                Button("Delete", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .confirmationDialog("Delete Network", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete network \"\(network.name)\"? This action cannot be undone.")
        }
    }
}
