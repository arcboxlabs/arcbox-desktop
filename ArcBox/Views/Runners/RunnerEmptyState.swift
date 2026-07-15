import SwiftUI

/// Shown when this Mac is not enrolled in any fleet yet.
struct RunnerEmptyState: View {
    let isWorking: Bool
    let canConnect: Bool
    let errorMessage: String?
    var actionTitle = "Connect to ArcBox"
    var onConnect: () -> Void

    private let chip = RunnerHostCapability.chipName

    var body: some View {
        EmptyStateView(icon: "hammer", title: "Turn this Mac into a CI runner") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run GitHub Actions jobs for your organization on this machine:")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{2022} \(chip)")
                    Text("\u{2022} Runtime capabilities are detected by the Fleet Agent")
                    Text("\u{2022} Jobs and settings stay under local agent control")
                }
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)

                Button(action: onConnect) {
                    HStack {
                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isWorking ? "Connecting…" : actionTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect)
                .padding(.top, 8)
                .accessibilityLabel(isWorking ? "Connecting this Mac to ArcBox" : actionTitle)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    RunnerEmptyState(isWorking: false, canConnect: true, errorMessage: nil, onConnect: {})
        .frame(width: 320, height: 520)
}
