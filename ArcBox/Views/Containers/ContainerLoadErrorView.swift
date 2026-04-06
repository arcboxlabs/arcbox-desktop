import SwiftUI

/// Error state shown when the initial container list fetch fails.
struct ContainerLoadErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        EmptyStateView(icon: "exclamationmark.triangle", title: "Failed to load containers") {
            VStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }
        }
    }
}
