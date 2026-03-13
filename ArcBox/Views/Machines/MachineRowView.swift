import SwiftUI

/// Single machine row in list (matches ContainerRowView pattern)
struct MachineRowView: View {
    let machine: MachineViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onStartStop: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    private var isStopped: Bool { !machine.isRunning }

    /// Generate a consistent color based on distro name
    private var distroColor: Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .cyan,
            .blue, .purple, .pink, .indigo, .teal,
        ]
        let hash = machine.distro.name.utf8.reduce(0) { acc, byte in
            acc &* 31 &+ Int(byte)
        }
        return colors[Int(hash.magnitude) % colors.count]
    }

    var body: some View {
        HStack(spacing: 8) {
            // Machine icon with status dot
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.white.opacity(0.12)
                            : AppColors.surfaceElevated
                    )
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(
                                isSelected
                                    ? AppColors.onAccent
                                    : (isStopped ? AppColors.textMuted : distroColor)
                            )
                    }

                // Status dot
                Circle()
                    .fill(machine.state.color)
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

            // Name + distro text
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? AppColors.onAccent
                            : (isStopped ? AppColors.textSecondary : AppColors.text)
                    )
                Text("\(machine.distro.version), \(machine.cpuCores) cores")
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
                    IconButton(
                        symbol: machine.isRunning ? "stop.fill" : "play.fill",
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
