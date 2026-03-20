import SwiftUI

/// A container row styled like a menu item in the menu bar popover.
struct MenuBarContainerRow: View {
    let container: ContainerViewModel
    let isSelected: Bool
    var onHoverStart: (() -> Void)? = nil
    let onSelect: () -> Void

    @State private var isHovering = false

    private var isHighlighted: Bool {
        isSelected || isHovering
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHighlighted ? 0.10 : 0.06))
                        .frame(width: 28, height: 28)

                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(container.image)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(container.state.color)
                    .frame(width: 8, height: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundShape.fill(isHighlighted ? AppColors.sidebarItemSelected : .clear))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(AppColors.accent)
                        .frame(width: 3, height: 22)
                        .padding(.leading, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                onHoverStart?()
            }
        }
        .accessibilityLabel("\(container.name), \(container.state.label)")
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }
}
