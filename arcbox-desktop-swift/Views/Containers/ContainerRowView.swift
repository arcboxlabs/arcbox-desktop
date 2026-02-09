import SwiftUI

/// Single container row in list
struct ContainerRowView: View {
    let container: ContainerViewModel
    let isSelected: Bool
    var indented: Bool = false
    let onSelect: () -> Void
    let onStartStop: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    /// Generate a consistent color based on image name
    private var containerColor: Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .cyan,
            .blue, .purple, .pink, .indigo, .teal,
        ]
        let hash = container.image.utf8.reduce(0) { acc, byte in
            acc &* 31 &+ Int(byte)
        }
        return colors[abs(hash) % colors.count]
    }

    var body: some View {
        HStack(spacing: 8) {
            // Container icon with status dot
            ZStack(alignment: .bottomTrailing) {
                // Container icon (colored box fallback)
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.12)
                            : AppColors.surfaceElevated
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 16))
                            .foregroundStyle(
                                isSelected ? AppColors.onAccent : containerColor
                            )
                    }

                // Status dot
                Circle()
                    .fill(container.state.color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? AppColors.selection : AppColors.background,
                                lineWidth: 2
                            )
                    )
                    .offset(x: 2, y: 2)
            }

            // Name + image text
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(container.image)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected
                            ? Color.white.opacity(0.67)
                            : AppColors.textSecondary
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons (show on hover or selection)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    IconButton(
                        symbol: container.isRunning ? "stop.fill" : "play.fill",
                        action: onStartStop,
                        color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                    )
                    IconButton(
                        symbol: "trash",
                        action: onDelete,
                        color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.leading, indented ? 28 : 0)
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
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
