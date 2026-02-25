import SwiftUI
import DockerClient

/// Column 2: networks list with toolbar
struct NetworksListView: View {
    @Environment(NetworksViewModel.self) private var vm
    @Environment(\.dockerClient) private var docker

    var body: some View {
        VStack(spacing: 0) {
            if vm.networks.isEmpty {
                NetworkEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.sortedNetworks) { network in
                            NetworkRowView(
                                network: network,
                                isSelected: vm.selectedID == network.id,
                                onSelect: { vm.selectNetwork(network.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Networks")
        .navigationSubtitle("\(vm.networkCount) total")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
                Button(action: { vm.showNewNetworkSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: Bindable(vm).showNewNetworkSheet) {
            NewNetworkSheet()
        }
        .task { await vm.loadNetworks(docker: docker) }
    }
}
