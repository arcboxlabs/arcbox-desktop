import SwiftUI

/// Collapsible compose project group
struct ContainerGroupView: View {
    let project: String
    let containers: [ContainerViewModel]
    let isExpanded: Bool
    let selectedID: String?
    let onToggle: () -> Void
    let onSelect: (String) -> Void
    let onStartStop: (String, Bool) -> Void
    let onDelete: (String) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Group header
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 14, height: 14)

                // Layer icon
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppColors.surfaceElevated)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accent)
                    }

                Text(project)
                    .font(.system(size: 13, weight: .medium))

                Spacer()
            }
            .frame(height: 36)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? AppColors.hover : Color.clear)
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { hovering in
                isHovered = hovering
            }

            // Container rows (if expanded)
            if isExpanded {
                ForEach(containers) { container in
                    ContainerRowView(
                        container: container,
                        isSelected: selectedID == container.id,
                        indented: true,
                        onSelect: { onSelect(container.id) },
                        onStartStop: { onStartStop(container.id, container.isRunning) },
                        onDelete: { onDelete(container.id) }
                    )
                }
            }
        }
    }
}
