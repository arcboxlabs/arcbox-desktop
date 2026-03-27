import SwiftUI

/// Column 3: service detail with tab-based toolbar
struct ServiceDetailView: View {
    @Environment(ServicesViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let service = vm.selectedService

        VStack(spacing: 0) {
            if let service {
                switch vm.activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "Name", value: service.name, rowIndex: 0)
                            InfoRow(label: "Namespace", value: service.namespace, rowIndex: 1)
                            InfoRow(label: "Type", value: service.type.rawValue, rowIndex: 2)
                            InfoRow(label: "Cluster IP", value: service.clusterIP ?? "None", rowIndex: 3)
                            InfoRow(label: "Ports", value: service.portsDisplay.isEmpty ? "None" : service.portsDisplay, rowIndex: 4)
                            InfoRow(label: "Created", value: service.createdAgo, rowIndex: 5)
                        }
                        .infoSectionStyle()
                        .padding(16)
                    }
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $vm.activeTab) {
                    ForEach(ServiceDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 120)
            }
        }
    }
}
