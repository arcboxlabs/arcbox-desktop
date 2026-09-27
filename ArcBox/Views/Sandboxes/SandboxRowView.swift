import SwiftUI

/// Single sandbox row
struct SandboxRowView: View {
    let sandbox: SandboxViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    var onStop: (() -> Void)?
    var onRemove: (() -> Void)?

    @State private var isHovered: Bool = false

    private var stateColor: Color {
        switch sandbox.state {
        case .starting: AppColors.warning
        case .ready, .running: AppColors.running
        case .stopping, .pausing: AppColors.warning
        case .stopped, .paused: AppColors.stopped
        case .failed: AppColors.error
        case .unknown: AppColors.stopped
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Sandbox icon
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.iconBackground)
                .frame(width: AppMetrics.rowIcon, height: AppMetrics.rowIcon)
                .overlay {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 14))
                        .foregroundStyle(stateColor)
                        .accessibilityHidden(true)
                }

            // Name and ID
            VStack(alignment: .leading, spacing: 2) {
                Text(sandbox.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(sandbox.shortID)
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
                if sandbox.state.isActive {
                    IconButton(
                        symbol: "stop.fill",
                        label: "Stop \(sandbox.displayName)",
                        action: { onStop?() },
                        color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                    )
                } else if sandbox.state.canRemove {
                    IconButton(
                        symbol: "trash.fill",
                        label: "Remove \(sandbox.displayName)",
                        action: { onRemove?() },
                        color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: AppMetrics.rowHeight)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(sandbox.displayName), \(sandbox.state.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { onSelect() }
    }
}
