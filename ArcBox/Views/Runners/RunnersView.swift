import FleetPlatformClient
import SwiftUI

/// This Mac as a Fleet runner host, backed by the local Agent watch stream.
struct RunnersView: View {
    @Environment(RunnersViewModel.self) private var vm
    @State private var isShowingWorkspaceDialog = false

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
            case .unenrolled:
                RunnerEmptyState(
                    isWorking: vm.isBusy,
                    errorMessage: vm.errorMessage,
                    onConnect: prepareEnrollment
                )
                .confirmationDialog(
                    "Connect this Mac to a workspace",
                    isPresented: $isShowingWorkspaceDialog,
                    titleVisibility: .visible
                ) {
                    ForEach(vm.workspaces) { workspace in
                        Button(workspaceButtonTitle(workspace), action: { enroll(in: workspace) })
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("ArcBox will issue a short-lived enrollment token and enroll the local Fleet Agent.")
                }
            case .enrolled(let host):
                VStack(spacing: 0) {
                    RunnerHostStatusBar(
                        host: host,
                        isPerformingAction: vm.isBusy,
                        onSetDraining: setDraining
                    )
                    if let errorMessage = vm.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    }
                    RunnerJobsView(jobs: host.inFlightJobs)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle("This Mac")
        .navigationSubtitle(vm.subtitle)
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

    private func workspaceButtonTitle(_ workspace: FleetWorkspace) -> String {
        "\(workspace.name) · \(workspace.plan)"
    }
}
