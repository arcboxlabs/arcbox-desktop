import FleetControlClient
import SwiftUI

struct RunnerHostOverviewPoolsSection: View {
    let host: RunnerHostViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Runner pools")
                .font(.headline)

            VStack(spacing: 0) {
                poolRow(
                    title: "macOS",
                    systemImage: "macwindow",
                    pool: .macOS
                )
                Divider()
                poolRow(
                    title: "Linux",
                    systemImage: "shippingbox",
                    pool: .linux
                )
            }
            .infoSectionStyle()
        }
    }

    private func poolRow(
        title: String,
        systemImage: String,
        pool: RunnerPoolOS
    ) -> some View {
        let capabilities = host.capabilities(for: pool)
        let activeJobCount = host.activeJobCount(for: pool)

        return HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(capabilityDescription(capabilities))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Text(statusDescription(capabilities: capabilities, activeJobCount: activeJobCount))
                .font(.caption)
                .foregroundStyle(capabilities.isEmpty ? AppColors.textSecondary : AppColors.running)
        }
        .padding(12)
    }

    private func capabilityDescription(_ capabilities: [FleetCapability]) -> String {
        guard !capabilities.isEmpty else { return "No capability reported by the Agent" }
        return capabilities.map { "\($0.arch) · \($0.backend.displayName)" }
            .joined(separator: ", ")
    }

    private func statusDescription(
        capabilities: [FleetCapability],
        activeJobCount: Int
    ) -> String {
        guard !capabilities.isEmpty else { return "Unavailable" }
        guard activeJobCount > 0 else { return "Available" }
        return "\(activeJobCount) active"
    }
}
