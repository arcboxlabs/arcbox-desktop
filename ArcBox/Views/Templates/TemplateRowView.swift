import SwiftUI

/// Single template row
struct TemplateRowView: View {
    let template: TemplateViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Template icon
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.iconBackground)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isSelected ? AppColors.onAccent : AppColors.textSecondary
                        )
                }

            // Name and specs
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text("\(template.cpuDisplay) / \(template.memoryDisplay)")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.67) : AppColors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            if isHovered || isSelected {
                IconButton(
                    symbol: "trash",
                    action: {},
                    color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                )
            }
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
