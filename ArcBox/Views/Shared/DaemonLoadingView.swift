import SwiftUI
import ArcBoxClient

/// Loading indicator shown while the arcbox daemon is starting or stopping.
struct DaemonLoadingView: View {
    let state: DaemonState

    private var message: String {
        switch state {
        case .stopping:
            return "Stopping ArcBox Daemon..."
        default:
            return "Starting ArcBox Daemon..."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
