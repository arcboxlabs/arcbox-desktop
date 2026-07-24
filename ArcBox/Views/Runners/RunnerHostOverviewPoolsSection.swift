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
                    capabilities: capabilities(for: "darwin")
                )
                Divider()
                poolRow(
                    title: "Linux",
                    systemImage: "shippingbox",
                    capabilities: capabilities(for: "linux")
                )
            }
            .infoSectionStyle()
        }
    }

    private func capabilities(for os: String) -> [FleetCapability] {
        host.capabilities.filter { $0.os == os }
    }

    private func poolRow(
        title: String,
        systemImage: String,
        capabilities: [FleetCapability]
    ) -> some View {
        HStack(spacing: 12) {
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

            Text(capabilities.isEmpty ? "Unavailable" : "Available")
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
}
