import ArcBoxClient
import SwiftUI

/// Column 2: row-based machine list (matches ContainersListView pattern)
struct MachinesView: View {
    @Environment(MachinesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.arcboxClient) private var client

    var body: some View {
        Group {
            if let orchestrator, !orchestrator.isReady {
                StartupProgressView(orchestrator: orchestrator)
            } else if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else if !daemonManager.setupPhase.isDockerReady {
                ProgressView(daemonManager.setupMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if client == nil {
                DaemonLoadingView(state: .registered)
            } else {
                MachinesListControllerView(
                    viewModel: vm,
                    onRetry: {
                        Task { await vm.loadMachines(client: client) }
                    },
                    onToggle: { id in
                        Task {
                            guard
                                let machine = vm.machines.first(where: { $0.id == id }),
                                !machine.isBusy
                            else {
                                return
                            }
                            if machine.isRunning {
                                await vm.stopMachine(id, client: client)
                            } else {
                                await vm.startMachine(id, client: client)
                            }
                        }
                    },
                    onDelete: { id in
                        Task {
                            guard
                                let machine = vm.machines.first(where: { $0.id == id }),
                                !machine.isBusy
                            else {
                                return
                            }
                            await vm.deleteMachine(id, client: client)
                        }
                    }
                )
            }
        }
        .navigationTitle("Machines")
        .navigationSubtitle(listSubtitle)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(
                    action: { vm.showCreateSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .accessibilityLabel("New machine")
                .disabled(
                    client == nil
                        || !daemonManager.state.isRunning
                        || !daemonManager.setupPhase.isDockerReady
                        || orchestrator?.isReady == false
                )
            }
        }
        .sheet(isPresented: Bindable(vm).showCreateSheet) {
            MachineCreateSheet()
        }
        .task(id: daemonManager.setupPhase.isDockerReady && client != nil) {
            guard daemonManager.setupPhase.isDockerReady, client != nil else { return }
            await vm.loadMachines(client: client)
        }
        // MachineEventMonitor streams MachineService.Events and posts this on
        // create/start/idle/stop/remove (and on the server's resync signal), so
        // the list tracks out-of-band changes — external CLI, a VM that exits on
        // its own, a machine reset to stopped after daemon recovery — without
        // polling. loadMachines preserves in-flight transition and detail state.
        .onReceive(NotificationCenter.default.publisher(for: .machineChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, client != nil else { return }
            Task { await vm.loadMachines(client: client) }
        }
        .listErrorToast(
            operationError: Bindable(vm).lastError,
            refreshError: Bindable(vm).refreshError,
            resourceName: "machines"
        )
    }

    private var listSubtitle: String {
        if let orchestrator, !orchestrator.isReady {
            return "Starting…"
        }
        guard daemonManager.state.isRunning, client != nil else {
            return "Waiting for daemon"
        }
        guard daemonManager.setupPhase.isDockerReady else {
            return "Starting…"
        }
        return switch vm.loadState {
        case .waiting:
            "Waiting for daemon"
        case .loading:
            "Loading…"
        case .loaded:
            "\(vm.runningCount) / \(vm.totalCount) running"
        case .failed:
            "Unavailable"
        }
    }
}

private struct MachinesListControllerView: NSViewControllerRepresentable {
    let viewModel: MachinesViewModel
    let onRetry: @MainActor () -> Void
    let onToggle: @MainActor (String) -> Void
    let onDelete: @MainActor (String) -> Void

    func makeNSViewController(context _: Context) -> MachinesListViewController {
        MachinesListViewController(
            viewModel: viewModel,
            onRetry: onRetry,
            onToggle: onToggle,
            onDelete: onDelete
        )
    }

    func updateNSViewController(
        _ controller: MachinesListViewController,
        context _: Context
    ) {
        controller.update(
            onRetry: onRetry,
            onToggle: onToggle,
            onDelete: onDelete
        )
    }
}
