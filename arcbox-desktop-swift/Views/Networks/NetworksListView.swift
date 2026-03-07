import SwiftUI
import ArcBoxClient
import DockerClient

/// Column 2: networks list with toolbar
struct NetworksListView: View {
    @Environment(NetworksViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.dockerClient) private var docker

    var body: some View {
        VStack(spacing: 0) {
            // "In Use" section header
            HStack {
                Text("In Use")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else if vm.networks.isEmpty {
                NetworkEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.sortedNetworks) { network in
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
            }
        }
        .sheet(isPresented: Bindable(vm).showNewNetworkSheet) {
            NewNetworkSheet()
        }
        .task(id: docker != nil) { await vm.loadNetworks(docker: docker) }
        .onReceive(NotificationCenter.default.publisher(for: .dockerNetworkChanged)) { _ in
            Task { await vm.loadNetworks(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await vm.loadNetworks(docker: docker) }
        }
    }
}
