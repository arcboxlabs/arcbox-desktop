import SwiftUI

/// Networks list + detail panel
struct NetworksListView: View {
    @State private var vm = NetworksViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left: list panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Networks")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(vm.networkCount) networks")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        IconButton(symbol: "arrow.up.arrow.down") {}
                        IconButton(symbol: "magnifyingglass") {}
                        IconButton(symbol: "plus") {}
                    }
                }
                .frame(height: 52)
                .padding(.horizontal, 16)
                .overlay(alignment: .bottom) { Divider() }

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
        .onAppear { vm.loadSampleData() }
    }
}
