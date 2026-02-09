import SwiftUI

/// Single network row
struct NetworkRowView: View {
    let network: NetworkViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Network icon
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.18) : AppColors.surfaceElevated)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: network.isSystem ? "globe" : "link")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isSelected ? AppColors.onAccent : AppColors.textSecondary
                        )
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
