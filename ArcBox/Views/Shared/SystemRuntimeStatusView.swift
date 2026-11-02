import ArcBoxClient
import SwiftUI

/// Fills a Docker-backed list while the daemon is up but its Docker runtime is not:
/// startup progress, a retryable failure, or why this Mac cannot run it at all.
struct SystemRuntimeStatusView: View {
    @Environment(DaemonManager.self) private var daemon
    @Environment(\.startupOrchestrator) private var orchestrator

    var body: some View {
        switch daemon.systemRuntimeIssue {
        case .hardwareVirtualizationUnavailable:
            // The daemon's reason says the same in platform terms; diagnostics keep it.
            ContentUnavailableView {
                Label("Virtualization Unavailable", systemImage: "cpu")
            } description: {
                Text(StartupProgressView.virtualizationUnavailableMessage)
            }
        case .failed(let reason):
            ContentUnavailableView {
                Label("Docker Runtime Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(reason.isEmpty ? "The Docker runtime failed to start." : reason)
            } actions: {
                if let orchestrator {
                    StartupRetryButton(orchestrator: orchestrator)
                        .buttonStyle(.borderedProminent)
                }
            }
        case .disabled(let reason):
            ContentUnavailableView {
                Label("System VM Is Disabled", systemImage: "pause.circle")
            } description: {
                Text(reason.isEmpty ? Self.disabledMessage : reason)
            }
        case nil:
            RuntimeProgressDetail(daemon: daemon)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static let disabledMessage = "The Docker runtime does not start automatically."
}

/// Retries startup, after a confirmation when the retry restarts the daemon, which stops
/// running Machines.
struct StartupRetryButton: View {
    let orchestrator: StartupOrchestrator
    var allowingAdministratorPrompt = false

    @State private var warning: String?

    var body: some View {
        Button("Retry") {
            Task {
                warning = await orchestrator.retryWarning()
                if warning == nil { await retry() }
            }
        }
        .alert(
            "Restart the ArcBox Daemon?",
            isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } }),
            presenting: warning
        ) { _ in
            Button("Restart and Retry", role: .destructive) {
                Task { await retry() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { warning in
            Text(warning)
        }
    }

    private func retry() async {
        await orchestrator.retry(allowingAdministratorPrompt: allowingAdministratorPrompt)
    }
}

/// What the runtime is doing while Docker starts: the daemon's current step, a download
/// it waits for, and a note that software emulation makes all of it slower.
struct RuntimeProgressDetail: View {
    let daemon: DaemonManager

    var body: some View {
        VStack(spacing: 8) {
            if let download = daemon.runtimeDownload, download.stage == .transferring {
                // A determinate bar replaces the spinner; onboarding's 190 pt frame has
                // no room for both. Verifying, installing and waiting to retry keep the
                // spinner: the daemon's reason says which.
                Text(daemon.runtimeProgressMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                downloadProgress(download)
            } else {
                ProgressView(daemon.runtimeProgressMessage)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
            }

            if daemon.isSoftwareEmulated {
                Label("Software emulation: startup takes a few minutes.", systemImage: "cpu")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.warning)
            }
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func downloadProgress(_ download: RuntimeDownloadProgress) -> some View {
        let received = formattedBytes(download.downloadedBytes)
        VStack(spacing: 4) {
            if let total = download.totalBytes, total > 0 {
                ProgressView(value: Double(min(download.downloadedBytes, total)), total: Double(total))
                    .frame(width: 220)
                Text("\(received) of \(formattedBytes(total))")
            } else {
                Text(received)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(AppColors.textMuted)
        .monospacedDigit()
    }
}
