import SwiftUI

/// Single volume row
struct VolumeRowView: View {
    let volume: VolumeViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Volume icon
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.18) : AppColors.surfaceElevated)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isSelected ? AppColors.onAccent : AppColors.textSecondary
                        )
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
                    symbol: "trash",
                    action: {},
                    color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(
            isSelected
                ? AppColors.selection
                : (isHovered ? AppColors.hover : Color.clear)
        )
        .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.text)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in isHovered = hovering }
    }
}
