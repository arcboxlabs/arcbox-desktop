import SwiftUI

/// Empty state shown when the Kubernetes feature is disabled
struct KubernetesDisabledView: View {
    var isStarting: Bool
    var startError: String?
    var onTurnOn: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "gear")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textMuted)

            Text(isStarting ? "Starting Kubernetes…" : "Kubernetes Disabled")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            if isStarting {
                ProgressView()
                    .controlSize(.regular)
            } else {
                if let error = startError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Button(action: onTurnOn) {
                    Text(startError != nil ? "Retry" : "Turn On")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
