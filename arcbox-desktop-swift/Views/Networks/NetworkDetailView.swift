import SwiftUI

/// Network detail panel with tabs
struct NetworkDetailView: View {
    let network: NetworkViewModel?
    @Binding var activeTab: NetworkDetailTab

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack {
                Spacer()
                Picker("Tab", selection: $activeTab) {
                    ForEach(NetworkDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
                Spacer()
            }
            .frame(height: 52)
            .overlay(alignment: .bottom) { Divider() }

            if let network {
                switch activeTab {
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
                    Spacer()
                    Text("Containers coming soon...")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
            } else {
                Spacer()
                Text("No Selection")
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}
