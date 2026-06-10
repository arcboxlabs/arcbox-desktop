import SwiftUI

/// Shown when this Mac is not enrolled in any fleet yet.
struct RunnerEmptyState: View {
    var onConnect: () -> Void

    private let chip = RunnerHostCapability.chipName
    private let macOSSlots = RunnerHostCapability.macOSGuestLimit
    private let linuxSlots = RunnerHostCapability.linuxRunnerEstimate

    var body: some View {
        EmptyStateView(icon: "hammer", title: "Turn this Mac into a CI runner") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run GitHub Actions jobs for your organization on this machine:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{2022} \(chip), ready for dual-runtime jobs")
                    Text("\u{2022} Up to \(macOSSlots) macOS VMs (ephemeral, isolated)")
                    Text("\u{2022} Up to \(linuxSlots) Linux containers via Docker")
                }
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)

                Button(action: onConnect) {
                    Text("Connect to ArcBox")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    RunnerEmptyState(onConnect: {})
        .frame(width: 320, height: 520)
}
