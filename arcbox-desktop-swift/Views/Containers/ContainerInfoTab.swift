import SwiftUI

/// Info tab content showing container details
struct ContainerInfoTab: View {
    let container: ContainerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Basic info section
                VStack(spacing: 0) {
                    InfoRow(label: "Name", value: container.name)
                    InfoRow(label: "ID", value: container.id)
                    InfoRow(label: "Image", value: container.image)
                    InfoRow(
                        label: "Status",
                        value: container.isRunning
                            ? "Up \(container.createdAgo)"
                            : "Stopped"
                    )
                    InfoRow(label: "Ports", value: container.portsDisplay)
                }

                // Resource usage (if running)
                if container.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resources")
                            .font(.system(size: 13, weight: .medium))

                        VStack(spacing: 0) {
                            InfoRow(
                                label: "CPU",
                                value: String(format: "%.1f%%", container.cpuPercent)
                            )
                            InfoRow(
                                label: "Memory",
                                value: String(
                                    format: "%.0f MB / %.0f MB",
                                    container.memoryMB,
                                    container.memoryLimitMB
                                )
                            )
                        }
                    }
                }

                // Labels section
                if !container.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Labels (\(container.labels.count))")
                            .font(.system(size: 13, weight: .medium))

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(
                                container.labels.sorted(by: { $0.key < $1.key }),
                                id: \.key
                            ) { key, value in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                    Text(value)
                                        .font(.system(size: 13, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
