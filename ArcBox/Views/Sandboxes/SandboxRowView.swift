import SwiftUI

/// Single sandbox row
struct SandboxRowView: View {
    let sandbox: SandboxViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    private var stateColor: Color {
        switch sandbox.state {
        case .running: AppColors.running
        case .paused: AppColors.warning
        case .stopped: AppColors.stopped
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Sandbox icon
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.iconBackground)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 14))
                        .foregroundStyle(stateColor)
                }

            // Name and template
            VStack(alignment: .leading, spacing: 2) {
                Text(sandbox.alias)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(sandbox.templateID)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.67) : AppColors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status badge
            StatusBadge(
                color: isSelected ? AppColors.onAccent : stateColor,
                label: sandbox.state.label
            )

            // Action buttons
            if isHovered || isSelected {
                IconButton(
                    symbol: sandbox.isRunning ? "stop.fill" : "trash.fill",
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
