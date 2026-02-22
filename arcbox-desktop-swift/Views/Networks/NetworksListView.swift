import SwiftUI

/// Networks list + detail panel
struct NetworksListView: View {
    @State private var vm = NetworksViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left: list panel
            VStack(spacing: 0) {
                // Network list or empty state
                if vm.networks.isEmpty {
                    NetworkEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.networks) { network in
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
            .frame(width: vm.listWidth)

            ListResizeHandle(width: $vm.listWidth, min: 200, max: 500)

            // Right: detail panel
            NetworkDetailView(
                network: vm.selectedNetwork,
                activeTab: $vm.activeTab
            )
        }
        .navigationTitle("Networks")
        .navigationSubtitle("\(vm.networkCount) total")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton()
                IconButton(symbol: "magnifyingglass") {}
                IconButton(symbol: "plus") {}
            }
        }
        .onAppear { vm.loadSampleData() }
    }
}
