import SwiftUI

/// Column 3: network detail with tab-based toolbar
struct NetworkDetailView: View {
    @Environment(NetworksViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let network = vm.selectedNetwork

        VStack(spacing: 0) {
            if let network {
                switch vm.activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "Name", value: network.name)
                            InfoRow(label: "ID", value: network.shortID)
                            InfoRow(label: "Driver", value: network.driver)
                            InfoRow(label: "Scope", value: network.scope)
                            InfoRow(label: "Created", value: network.createdAgo)
                            InfoRow(label: "Internal", value: network.`internal` ? "Yes" : "No")
                            InfoRow(label: "Attachable", value: network.attachable ? "Yes" : "No")
                            InfoRow(label: "Containers", value: network.usageDisplay)
                        }
                        .padding(16)
                    }
                case .containers:
                    NetworkContainersTab(network: network)
                }
            } else {
                Spacer()
                Text("No Selection")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 15))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $vm.activeTab) {
                    ForEach(NetworkDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
    }
}
