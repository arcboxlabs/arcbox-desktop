import SwiftUI

/// Empty state shown when the Kubernetes feature is disabled
struct KubernetesDisabledView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "gear")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))

            Text("Kubernetes Disabled")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Button(action: {}) {
                Text("Turn On")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
