import SwiftUI

/// Shared runner image preparation state rendered in the runner workflow.
struct RunnerImagePreparationStatusView: View {
    let agent: RunnerAgentViewModel

    var body: some View {
        let readiness = agent.runnerImageReadiness

        if readiness != .hidden {
            HStack(alignment: .center, spacing: 10) {
                Group {
                    switch readiness {
                    case .hidden:
                        EmptyView()
                    case .pending(let reference):
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("macOS runner image needs preparation")
                                Text(reference)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                    case .preparing(let progress):
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Preparing macOS runner image", systemImage: "shippingbox")
                            ProgressView(value: progress.fraction)
                            Text(progress.displayDescription)
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    case .restartRequired:
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Runner Agent restart required")
                                Text(
                                    "The service manager must restart the Runner Agent before the VM backend becomes available. ArcBox will keep watching."
                                )
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                    case .completed(let reference):
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("macOS runner image prepared")
                                Text(reference)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.running)
                        }
                    case .failed(let message):
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Image preparation failed")
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppColors.error)
                        }
                    }
                }

                Spacer(minLength: 8)

                switch readiness {
                case .pending:
                    Button(
                        "Prepare Image",
                        systemImage: "arrow.down.circle",
                        action: agent.beginMacOSRunnerImagePreparation
                    )
                    .controlSize(.small)
                    .disabled(!agent.canBeginMacOSRunnerImagePreparation)
                case .failed:
                    Button(
                        "Retry",
                        systemImage: "arrow.clockwise",
                        action: agent.beginMacOSRunnerImagePreparation
                    )
                    .controlSize(.small)
                    .disabled(!agent.canBeginMacOSRunnerImagePreparation)
                case .hidden, .preparing, .restartRequired, .completed:
                    EmptyView()
                }
            }
            .padding(10)
            .background(AppColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}
