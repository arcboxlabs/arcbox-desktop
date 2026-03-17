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

    private var isStopped: Bool { !container.isRunning && !container.isTransitioning }

    /// Port mappings that can be opened as links.
    /// With a container IP, all ports are reachable via arcbox.local.
    /// Without one, only ports with a valid host mapping (hostPort > 0) are useful.
    private var linkablePorts: [PortMapping] {
        if container.ipAddress != nil {
            return container.ports
        }
        return container.ports.filter { $0.hostPort > 0 }
    }

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

    private func openContainerURL(mapping: PortMapping) {
        // Prefer arcbox.local domain (resolves to container's real IP via DNS).
        // Use containerPort for arcbox.local (service listens on that port inside the container).
        // Use hostPort for localhost (port forwarded to the host).
        let urlString: String
        if let domain = container.arcboxDomain, container.ipAddress != nil {
            urlString = "http://\(domain):\(mapping.containerPort)"
        } else {
            urlString = "http://localhost:\(mapping.hostPort)"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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
                                isSelected
                                    ? AppColors.onAccent
                                    : (isStopped ? AppColors.textMuted : containerColor)
                            )
                    }

                // Status dot
                if container.isTransitioning {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                        .offset(x: 2, y: 2)
                } else {
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
            }

            // Name + image text
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? AppColors.onAccent
                            : (isStopped ? AppColors.textSecondary : AppColors.text)
                    )
                Text(container.image)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected
                            ? Color.white.opacity(0.67)
                            : (isStopped ? AppColors.textMuted : AppColors.textSecondary)
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons (show on hover or selection)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    // Link button for containers with port mappings
                    if !linkablePorts.isEmpty {
                        if linkablePorts.count == 1,
                           let mapping = linkablePorts.first
                        {
                            IconButton(
                                symbol: "link",
                                action: { openContainerURL(mapping: mapping) },
                                color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                            )
                        } else {
                            Menu {
                                ForEach(linkablePorts) { mapping in
                                    if let domain = container.arcboxDomain, container.ipAddress != nil {
                                        Button("\(domain):\(mapping.containerPort)") {
                                            openContainerURL(mapping: mapping)
                                        }
                                    } else {
                                        Button("localhost:\(mapping.hostPort)") {
                                            openContainerURL(mapping: mapping)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "link")
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        isSelected ? AppColors.onAccent : AppColors.textSecondary
                                    )
                                    .frame(width: 26, height: 26)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }

                    if container.isTransitioning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 26, height: 26)
                    } else {
                        IconButton(
                            symbol: container.isRunning ? "stop.fill" : "play.fill",
                            action: onStartStop,
                            color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                        )
                    }
                    IconButton(
                        symbol: "trash",
                        action: onDelete,
                        color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                    )
                }
            }
        }
        .padding(.horizontal, 12)
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
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
