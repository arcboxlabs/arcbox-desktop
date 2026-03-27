import ArcBoxClient
import SwiftUI

/// Single container row in list
struct ContainerRowView: View {
    let container: ContainerViewModel
    let isSelected: Bool
    var indented: Bool = false
    let onSelect: () -> Void
    let onStartStop: () -> Void
    let onDelete: () -> Void

    @Environment(DaemonManager.self) private var daemonManager
    @State private var isHovered: Bool = false
    @State private var showDeleteConfirm = false

    private var isStopped: Bool { !container.isRunning && !container.isTransitioning }

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

    private var useDNS: Bool { daemonManager.dnsResolverInstalled && daemonManager.routeInstalled }

    private var hostDomain: String {
        useDNS ? "\(container.name).arcbox.local" : "localhost"
    }

    private func openPort(_ port: PortMapping) {
        let urlString: String
        if useDNS {
            let suffix = port.containerPort == 80 ? "" : ":\(port.containerPort)"
            urlString = "http://\(hostDomain)\(suffix)"
        } else {
            urlString = "http://localhost:\(port.hostPort)"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Container icon with status dot
            ZStack(alignment: .bottomTrailing) {
                RemoteIconView(
                    iconURL: container.iconURL,
                    size: 32,
                    foregroundColor: isStopped ? AppColors.textMuted : containerColor,
                    backgroundColor: AppColors.iconBackground
                )

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
                    let activePorts = useDNS ? container.ports : container.ports.filter { $0.hostPort > 0 }
                    if !activePorts.isEmpty {
                        if activePorts.count == 1,
                            let port = activePorts.first
                        {
                            IconButton(
                                symbol: "link",
                                action: { openPort(port) },
                                color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                            )
                        } else {
                            Menu {
                                ForEach(activePorts) { port in
                                    let displayPort = useDNS ? port.containerPort : port.hostPort
                                    let title = (useDNS && displayPort == 80)
                                        ? hostDomain
                                        : "\(hostDomain):\(displayPort)"
                                    Button(title) {
                                        openPort(port)
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
                        symbol: "trash.fill",
                        action: { showDeleteConfirm = true },
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
        .confirmationDialog("Delete Container", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(container.name)\"? This action cannot be undone.")
        }
    }
}
