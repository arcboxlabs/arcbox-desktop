import SwiftUI

/// Single pod row
struct PodRowView: View {
    let pod: PodViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Pod icon
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.iconBackground)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "cube")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }

            // Name and namespace
            VStack(alignment: .leading, spacing: 2) {
                Text(pod.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(pod.namespace)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.67) : AppColors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Phase indicator
            Circle()
                .fill(pod.phase.color)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 8)
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
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in isHovered = hovering }
    }
}
