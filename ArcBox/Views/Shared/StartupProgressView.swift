import SwiftUI
import ArcBoxClient

/// Progress view shown during the startup sequence.
/// Replaces DaemonLoadingView for the initial startup phase.
/// After startup completes, DaemonLoadingView handles daemon disconnect/stop.
struct StartupProgressView: View {
    let orchestrator: StartupOrchestrator

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(StartupStep.allCases) { step in
                    stepRow(step)
                }
            }
            .padding(.horizontal, 40)

            if case .failed(_, let message) = orchestrator.phase {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.error)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        Task { await orchestrator.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stepRow(_ step: StartupStep) -> some View {
        let status = orchestrator.stepStatuses[step] ?? .pending

        HStack(spacing: 8) {
            statusIcon(status)
                .frame(width: 14, height: 14)

            Text(step.label)
                .font(.system(size: 12))
                .foregroundStyle(textColor(for: status))
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textMuted)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.running)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.error)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textMuted)
        }
    }

    private func textColor(for status: StepStatus) -> Color {
        switch status {
        case .pending, .skipped: return AppColors.textMuted
        case .running: return AppColors.textSecondary
        case .completed: return AppColors.textSecondary
        case .failed: return AppColors.error
        }
    }
}
