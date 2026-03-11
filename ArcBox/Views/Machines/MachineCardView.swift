import SwiftUI

/// Machine card with specs + actions
struct MachineCardView: View {
    let machine: MachineViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onStartStop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                Text("\u{1F427}")
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name)
                        .font(.system(size: 13))
                    Text(machine.distro.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                StatusBadge(color: machine.state.color, label: machine.state.label)
            }

            // Divider
            Divider()
                .padding(.vertical, 12)

            // Resource info
            HStack(spacing: 16) {
                Text("CPU: \(machine.cpuCores) cores")
                Text("Memory: \(machine.memoryGB) GB")
                Text("Disk: \(machine.diskGB) GB")
            }
            .font(.system(size: 13))
            .foregroundStyle(AppColors.textSecondary)

            // IP address (if running)
            if let ip = machine.ipAddress {
                Text("IP: \(ip)")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 8)
            }

            // Action buttons
            HStack(spacing: 8) {
                if machine.isRunning {
                    Button("Terminal") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Files") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Stop", action: onStartStop)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("Start", action: onStartStop)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.top, 16)
        }
        .padding(16)
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? AppColors.accent : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
