import SwiftUI

/// Column 3: network detail (single-page layout)
struct NetworkDetailView: View {
    @Environment(NetworksViewModel.self) private var vm

    var body: some View {
        let network = vm.selectedNetwork

        VStack(spacing: 0) {
            if let network {
                ScrollView {
                    VStack(spacing: 0) {
                        // Info section
                        InfoRow(label: "Name", value: network.name)
                        InfoRow(label: "ID", value: network.shortID)
                        InfoRow(label: "Driver", value: network.driver)
                        InfoRow(label: "Scope", value: network.scope)
                        InfoRow(label: "Created", value: network.createdAgo)
                        InfoRow(label: "Internal", value: network.`internal` ? "Yes" : "No")
                        InfoRow(label: "Attachable", value: network.attachable ? "Yes" : "No")
                        InfoRow(label: "Containers", value: network.usageDisplay)
                    }
                    .infoSectionStyle()
                    .padding(16)

                    // Connected containers section
                    NetworkContainersSection(network: network)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.textMuted)
                    Text("No Selection")
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.system(size: 15))
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Spacer()
            }
        }
    }
}
