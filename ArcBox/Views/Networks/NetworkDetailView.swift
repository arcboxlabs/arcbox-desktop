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
                        InfoRow(label: "Name", value: network.name, rowIndex: 0)
                        InfoRow(label: "ID", value: network.shortID, rowIndex: 1)
                        InfoRow(label: "Driver", value: network.driver, rowIndex: 2)
                        InfoRow(label: "Scope", value: network.scope, rowIndex: 3)
                        InfoRow(label: "Created", value: network.createdAgo, rowIndex: 4)
                        InfoRow(label: "Internal", value: network.`internal` ? "Yes" : "No", rowIndex: 5)
                        InfoRow(label: "Attachable", value: network.attachable ? "Yes" : "No", rowIndex: 6)
                        InfoRow(label: "Containers", value: network.usageDisplay, rowIndex: 7)
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
                Text("Info")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
