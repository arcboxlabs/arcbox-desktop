import ArcBoxClient
import SwiftUI

/// Transitional SwiftUI toolbar and lifecycle host for the native Services list.
struct ServicesListView: View {
    @Environment(KubernetesState.self) private var k8s
    @Environment(ServicesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.arcboxClient) private var arcboxClient

    var body: some View {
        Group {
            if let orchestrator, !orchestrator.isReady {
                StartupProgressView(orchestrator: orchestrator)
            } else if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else if !daemonManager.setupPhase.isDockerReady {
                ProgressView(daemonManager.setupMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if arcboxClient == nil {
                DaemonLoadingView(state: .registered)
            } else {
                ServicesListControllerView(
                    state: k8s,
                    viewModel: vm,
                    canControl: true,
                    onCheckStatus: {
                        Task { await k8s.checkStatus(client: arcboxClient) }
                    },
                    onStart: {
                        Task { await k8s.start(client: arcboxClient) }
                    },
                    onStop: {
                        Task { await k8s.stop(client: arcboxClient) }
                    },
                    onRetryStreams: {
                        k8s.retryStreams(client: arcboxClient)
                    }
                )
            }
        }
        .navigationTitle("Services")
        .navigationSubtitle(navigationSubtitle)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue {
                vm.searchText = ""
            }
        }
        .task(id: daemonManager.setupPhase.isDockerReady && arcboxClient != nil) {
            guard daemonManager.setupPhase.isDockerReady, arcboxClient != nil else { return }
            await k8s.checkStatus(client: arcboxClient)
        }
    }

    private var navigationSubtitle: String {
        if case .error = daemonManager.state {
            return "Unavailable"
        }
        if orchestrator?.isReady == false || !daemonManager.state.isRunning
            || !daemonManager.setupPhase.isDockerReady
        {
            return "Starting…"
        }
        guard arcboxClient != nil else { return "Unavailable" }
        return switch k8s.lifecycle {
        case .checking: "Checking"
        case .disabled: "Disabled"
        case .starting: "Starting"
        case .ready: "\(vm.serviceCount) total"
        case .stopping: "Stopping"
        case .failed: "Unavailable"
        }
    }
}

private struct ServicesListControllerView: NSViewControllerRepresentable {
    let state: KubernetesState
    let viewModel: ServicesViewModel
    let canControl: Bool
    let onCheckStatus: @MainActor () -> Void
    let onStart: @MainActor () -> Void
    let onStop: @MainActor () -> Void
    let onRetryStreams: @MainActor () -> Void

    func makeNSViewController(context _: Context) -> ServicesListViewController {
        ServicesListViewController(
            state: state,
            viewModel: viewModel,
            canControl: canControl,
            onCheckStatus: onCheckStatus,
            onStart: onStart,
            onStop: onStop,
            onRetryStreams: onRetryStreams
        )
    }

    func updateNSViewController(
        _ controller: ServicesListViewController,
        context _: Context
    ) {
        controller.update(
            canControl: canControl,
            onCheckStatus: onCheckStatus,
            onStart: onStart,
            onStop: onStop,
            onRetryStreams: onRetryStreams
        )
    }
}
