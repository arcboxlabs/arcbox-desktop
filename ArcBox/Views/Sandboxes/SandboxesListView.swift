import ArcBoxClient
import SwiftUI

/// Column 2: sandbox list and lifecycle actions.
struct SandboxesListView: View {
    @Environment(SandboxesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.arcboxClient) private var client

    @State private var sandboxToRemove: SandboxViewModel?

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
                sandboxListContent
            }
        }
        .navigationTitle("Sandboxes")
        .navigationSubtitle(listSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                    .disabled(!sandboxActionsAvailable)
                Button(
                    action: { vm.showNewSandboxSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .help("New Sandbox")
                .disabled(!sandboxActionsAvailable)
            }
        }
        .task(id: daemonManager.setupPhase.isDockerReady && client != nil) {
            guard daemonManager.setupPhase.isDockerReady, client != nil else { return }
            await vm.loadSandboxes(client: client)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sandboxChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, client != nil else { return }
            Task {
                await vm.loadSandboxes(client: client)
                if let id = vm.selectedID, vm.sandboxes.contains(where: { $0.id == id }) {
                    await vm.loadSandboxDetails(id, client: client)
                }
            }
        }
        .confirmationDialog(
            "Remove Sandbox",
            isPresented: Binding(
                get: { sandboxToRemove != nil },
                set: { if !$0 { sandboxToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let sandbox = sandboxToRemove {
                Button("Remove \"\(sandbox.displayName)\"", role: .destructive) {
                    Task {
                        await vm.removeSandbox(sandbox.id, force: true, client: client)
                    }
                }
            }
            Button("Cancel", role: .cancel) { sandboxToRemove = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { !vm.showNewSandboxSheet && vm.lastError != nil },
                set: { if !$0 { vm.clearError() } }
            )
        ) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.lastError ?? "")
        }
        .sheet(isPresented: Bindable(vm).showNewSandboxSheet) {
            NewSandboxSheet()
        }
        .errorToast(message: Bindable(vm).refreshError)
    }

    private var sandboxActionsAvailable: Bool {
        (orchestrator?.isReady ?? true)
            && daemonManager.state.isRunning
            && daemonManager.setupPhase.isDockerReady
            && client != nil
    }

    @ViewBuilder
    private var sandboxListContent: some View {
        switch vm.loadState {
        case .waiting:
            loadingPlaceholder("Waiting for ArcBox daemon…")
        case .loading:
            loadingPlaceholder("Loading sandboxes…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Sandboxes", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task {
                        await vm.loadSandboxes(client: client)
                    }
                }
                .disabled(client == nil)
            }
        case .loaded:
            if vm.sandboxes.isEmpty {
                SandboxEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.sortedSandboxes) { sandbox in
                            SandboxRowView(
                                sandbox: sandbox,
                                isSelected: vm.selectedID == sandbox.id,
                                onSelect: { vm.selectSandbox(sandbox.id) },
                                onStop: {
                                    Task { await vm.stopSandbox(sandbox.id, client: client) }
                                },
                                onRemove: {
                                    sandboxToRemove = sandbox
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var listSubtitle: String {
        if let orchestrator, !orchestrator.isReady {
            return "Starting…"
        }
        guard daemonManager.state.isRunning else {
            return "Unavailable"
        }
        guard daemonManager.setupPhase.isDockerReady else {
            return "Starting…"
        }
        guard client != nil else {
            return "Connecting…"
        }

        return switch vm.loadState {
        case .waiting:
            "Waiting for daemon"
        case .loading:
            "Loading…"
        case .loaded:
            "\(vm.sandboxCount) total"
        case .failed:
            "Unavailable"
        }
    }

    private func loadingPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
