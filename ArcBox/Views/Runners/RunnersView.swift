import ArcBoxAuth
internal import AuthenticationServices
import FleetPlatformClient
import SwiftUI

/// This Mac as a Fleet runner host, backed by the local Agent watch stream.
struct RunnersView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(RunnersViewModel.self) private var vm
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isShowingWorkspaceDialog = false
    @State private var isShowingEnrollmentResetConfirmation = false

    var body: some View {
        Group {
            switch vm.viewState {
            case .connecting:
                ProgressView("Connecting to Fleet Agent…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable(let message):
                EmptyStateView(icon: "exclamationmark.triangle", title: "Fleet Agent unavailable") {
                    VStack(spacing: 6) {
                        Text(message)
                        Text("ArcBox will keep trying to reconnect.")
                    }
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                }
            case .signedOut:
                signedOutView
            case .unenrolled:
                onboardingView(errorMessage: vm.errorMessage)
            case .enrolling(let progress):
                enrollmentProgressView(progress)
            case .enrollmentFailed(let message, let recovery):
                switch recovery {
                case .retry:
                    onboardingView(errorMessage: message, actionTitle: "Try Again")
                case .waitForAgent:
                    enrollmentBlockedView(message: message, recovery: recovery)
                case .unenroll:
                    enrollmentBlockedView(message: message, recovery: recovery)
                }
            case .failed(let message):
                EmptyStateView(icon: "exclamationmark.octagon", title: "Fleet integration unavailable") {
                    VStack(spacing: 6) {
                        Text(message)
                        Text("Check the ArcBox configuration and Fleet Agent compatibility.")
                    }
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                }
            case .enrolled(let host, let freshness):
                VStack(spacing: 0) {
                    RunnerHostStatusBar(
                        host: host,
                        isPerformingAction: vm.isBusy || freshness.isReconnecting,
                        isReconnecting: freshness.isReconnecting,
                        onSetDraining: setDraining,
                        onUnenroll: unenroll
                    )
                    if let statusMessage = hostStatusMessage(freshness: freshness) {
                        Label(statusMessage, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else if let errorMessage = vm.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    }
                    RunnerImagePreparationStatusView(fleet: vm.fleet)
                    RunnerJobsView(jobs: host.inFlightJobs)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle("This Mac")
        .navigationSubtitle(vm.subtitle)
    }

    private var signedOutView: some View {
        EmptyStateView(icon: "person.crop.circle.badge.exclamationmark", title: "Sign in to connect this Mac") {
            VStack(spacing: 12) {
                Text("Sign in with your ArcBox account before choosing a Fleet workspace.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: signIn) {
                    HStack {
                        if authSession.status == .signingIn {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(authSession.status == .signingIn ? "Signing In…" : "Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(
                    authSession.status == .signingIn
                        || authSession.configuration.isPlaceholder
                )
                .accessibilityLabel(
                    authSession.status == .signingIn ? "Signing in to ArcBox" : "Sign in to ArcBox"
                )

                if let authMessage {
                    Label(authMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var authMessage: String? {
        if authSession.configuration.isPlaceholder {
            return "No OIDC provider is configured for this build."
        }
        if case .error(let message) = authSession.status {
            return message
        }
        return nil
    }

    private func enrollmentProgressView(_ progress: RunnerEnrollmentProgress) -> some View {
        EmptyStateView(icon: "arrow.triangle.2.circlepath", title: progress.title) {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(progress.message)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(progress.title). \(progress.message)")
        }
    }

    private func onboardingView(
        errorMessage: String?,
        actionTitle: String = "Connect to ArcBox"
    ) -> some View {
        RunnerEmptyState(
            isWorking: vm.isBusy,
            canConnect: vm.canConnect,
            errorMessage: errorMessage,
            actionTitle: actionTitle,
            onConnect: prepareEnrollment
        )
        .confirmationDialog(
            "Connect this Mac to a workspace",
            isPresented: $isShowingWorkspaceDialog,
            titleVisibility: .visible
        ) {
            ForEach(vm.workspaces) { workspace in
                Button(workspaceButtonTitle(workspace), action: { enroll(in: workspace) })
                    .disabled(vm.isBusy)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ArcBox will issue a short-lived enrollment token and enroll the local Fleet Agent.")
        }
    }

    private func enrollmentBlockedView(
        message: String,
        recovery: RunnerEnrollmentRecovery
    ) -> some View {
        EmptyStateView(
            icon: recovery == .waitForAgent ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle",
            title: recovery == .waitForAgent ? "Confirming enrollment" : "Enrollment needs attention"
        ) {
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(message)
                    if recovery == .waitForAgent {
                        Text(
                            "ArcBox will keep observing the local Fleet Agent. A new enrollment will not start until the Agent reports a conclusive state."
                        )
                    } else {
                        Text("Unenroll the local Agent before starting another enrollment attempt.")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                if recovery == .waitForAgent {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Waiting for Fleet Agent enrollment state")
                } else {
                    Button("Unenroll and Start Over…", role: .destructive) {
                        isShowingEnrollmentResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isBusy)
                    .accessibilityHint("Removes the local Agent enrollment so this Mac can enroll again")
                    .confirmationDialog(
                        "Unenroll this Mac and start over?",
                        isPresented: $isShowingEnrollmentResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Unenroll", role: .destructive, action: unenroll)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "This removes the local Fleet Agent's enrollment credentials and allows a new "
                                + "enrollment attempt. It does not stop or uninstall the Agent."
                        )
                    }
                }

                if let actionError = vm.errorMessage, actionError != message {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func prepareEnrollment() {
        Task {
            if await vm.prepareEnrollment() {
                isShowingWorkspaceDialog = true
            }
        }
    }

    private func enroll(in workspace: FleetWorkspace) {
        Task {
            await vm.enroll(in: workspace)
        }
    }

    private func setDraining(_ draining: Bool) {
        Task {
            await vm.setDraining(draining)
        }
    }

    private func unenroll() {
        Task {
            await vm.unenroll()
        }
    }

    private func signIn() {
        Task {
            await authSession.signIn(using: webAuthenticationSession)
        }
    }

    private func hostStatusMessage(freshness: RunnerHostFreshness) -> String? {
        guard case .reconnecting(let message) = freshness else { return nil }
        return "Live Fleet Agent updates are paused. \(message) ArcBox is reconnecting."
    }

    private func workspaceButtonTitle(_ workspace: FleetWorkspace) -> String {
        "\(workspace.name) · \(workspace.plan)"
    }
}

extension RunnerHostFreshness {
    fileprivate var isReconnecting: Bool {
        if case .reconnecting = self { return true }
        return false
    }
}
