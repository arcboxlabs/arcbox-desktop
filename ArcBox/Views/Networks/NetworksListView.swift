import SwiftUI
import ArcBoxClient
import DockerClient

/// Column 2: networks list with toolbar
struct NetworksListView: View {
    @Environment(NetworksViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.dockerClient) private var docker

    var body: some View {
        VStack(spacing: 0) {
            if let orchestrator, !orchestrator.isReady {
                StartupProgressView(orchestrator: orchestrator)
            } else if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else if vm.networks.isEmpty {
                NetworkEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !inUseNetworks.isEmpty {
                            sectionHeader("In Use")
                            ForEach(inUseNetworks) { network in
                                networkRow(network)
                            }
                        }
                        if !unusedNetworks.isEmpty {
                            sectionHeader("Unused")
                            ForEach(unusedNetworks) { network in
                                networkRow(network)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Networks")
        .navigationSubtitle("\(vm.networkCount) total")
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: { vm.showNewNetworkSheet = true }) {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: Bindable(vm).showNewNetworkSheet) {
            NewNetworkSheet()
        }
        .errorToast(message: Bindable(vm).lastError)
        .task(id: docker != nil) { await vm.loadNetworks(docker: docker) }
        .onReceive(NotificationCenter.default.publisher(for: .dockerNetworkChanged)) { _ in
            Task { await vm.loadNetworks(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await vm.loadNetworks(docker: docker) }
        }
    }

    private var inUseNetworks: [NetworkViewModel] {
        vm.sortedNetworks.filter { $0.containerCount > 0 }
    }

    private var unusedNetworks: [NetworkViewModel] {
        vm.sortedNetworks.filter { $0.containerCount == 0 }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func networkRow(_ network: NetworkViewModel) -> some View {
        NetworkRowView(
            network: network,
            isSelected: vm.selectedID == network.id,
            onSelect: { vm.selectNetwork(network.id) },
            onDelete: {
                Task { await vm.removeNetwork(network.id, docker: docker) }
            }
        )
    }
}
