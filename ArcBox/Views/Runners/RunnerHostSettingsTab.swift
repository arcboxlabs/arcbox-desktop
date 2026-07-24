import FleetControlClient
import SwiftUI

struct RunnerHostSettingsTab: View {
    let host: RunnerHostViewModel
    let settings: FleetAgentSettings?

    @Environment(RunnersViewModel.self) private var runners
    @State private var isConfirmingUnenroll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                participationSection
                networkSection
                serviceSection
                controlsSection

                if let errorMessage = runners.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
            .padding(16)
        }
    }

    private var participationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Participation")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "State", value: host.isDraining ? "Draining" : "Accepting jobs")
                InfoRow(
                    label: "Agent policy",
                    value: settingDescription(settings?.participate) { $0 ? "Enabled" : "Disabled" }
                )
                InfoRow(
                    label: "Load ceiling",
                    value: settingDescription(settings?.loadCeiling) {
                        $0.formatted(.number.precision(.fractionLength(2)))
                    }
                )
                InfoRow(
                    label: "Memory reserve",
                    value: settingDescription(settings?.memFloorMib) {
                        "\($0.formatted()) MiB"
                    }
                )
            }
            .infoSectionStyle()
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(
                    label: "Fleet gateway",
                    value: settingDescription(settings?.gateway) {
                        $0.isEmpty ? "Not configured" : $0
                    }
                )
            }
            .infoSectionStyle()
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fleet Agent service")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Process manager", value: "launchd / service daemon")
                InfoRow(label: "Desktop responsibility", value: "Local gRPC client only")
            }
            .infoSectionStyle()

            Text(
                "Starting, stopping, updating, and installing the Fleet Agent are handled outside ArcBox Desktop."
            )
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls")
                .font(.headline)

            Button(
                host.isDraining ? "Resume accepting jobs" : "Drain this runner",
                systemImage: host.isDraining ? "play.fill" : "pause.fill",
                action: toggleDrainState
            )
            .disabled(runners.isBusy || !host.status.canChangeDrainState)

            Divider()

            Button(
                "Remove this runner",
                systemImage: "trash",
                role: .destructive
            ) {
                isConfirmingUnenroll = true
            }
            .disabled(runners.isBusy)
            .confirmationDialog(
                "Remove this runner?",
                isPresented: $isConfirmingUnenroll,
                titleVisibility: .visible
            ) {
                Button("Remove Runner", role: .destructive, action: unenroll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(unenrollMessage)
            }
        }
    }

    private var unenrollMessage: String {
        let credentialMessage =
            "This removes the Fleet credential from the local Agent. It does not stop or uninstall the Agent."
        guard host.activeJobCount > 0 else { return credentialMessage }
        let jobLabel = host.activeJobCount == 1 ? "job" : "jobs"
        return "The Agent reports \(host.activeJobCount) active \(jobLabel). \(credentialMessage)"
    }

    private func toggleDrainState() {
        Task {
            await runners.setDraining(!host.isDraining)
        }
    }

    private func unenroll() {
        Task {
            await runners.unenroll()
        }
    }

    private func settingDescription<Value>(
        _ setting: FleetSetting<Value>?,
        format: (Value) -> String
    ) -> String {
        guard let setting else { return "Not reported" }
        let target = format(setting.target)
        guard setting.isPending else { return target }
        return "\(target) (pending; current: \(format(setting.current)))"
    }
}
