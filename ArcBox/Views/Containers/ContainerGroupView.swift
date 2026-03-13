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
    let onStartStopAll: ([String], Bool) -> Void
    let onDeleteAll: ([String]) -> Void

    @State private var isHovered: Bool = false

    private var hasAnyRunning: Bool {
        containers.contains(where: \.isRunning)
    }

    private var isAnyTransitioning: Bool {
        containers.contains(where: \.isTransitioning)
    }

    private var allContainerIDs: [String] {
        containers.map(\.id)
    }

    private var runningCount: Int {
        containers.filter(\.isRunning).count
    }

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
                            .foregroundStyle(hasAnyRunning ? AppColors.accent : AppColors.textMuted)
                    }

                Text(project)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hasAnyRunning ? AppColors.text : AppColors.textSecondary)

                Text("\(runningCount)/\(containers.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                // Group action buttons (show on hover)
                if isHovered {
                    HStack(spacing: 4) {
                        if isAnyTransitioning {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 26, height: 26)
                        } else {
                            IconButton(
                                symbol: hasAnyRunning ? "stop.fill" : "play.fill",
                                action: { onStartStopAll(allContainerIDs, hasAnyRunning) },
                                color: AppColors.textSecondary
                            )
                        }
                        IconButton(
                            symbol: "trash",
                            action: { onDeleteAll(allContainerIDs) },
                            color: AppColors.textSecondary
                        )
                    }
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? AppColors.hover : Color.clear)
            )
            .padding(.horizontal, 12)
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
