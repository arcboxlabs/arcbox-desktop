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
                            InfoRow(label: "Name", value: service.name)
                            InfoRow(label: "Namespace", value: service.namespace)
                            InfoRow(label: "Type", value: service.type.rawValue)
                            InfoRow(label: "Cluster IP", value: service.clusterIP ?? "None")
                            InfoRow(label: "Ports", value: service.portsDisplay.isEmpty ? "None" : service.portsDisplay)
                            InfoRow(label: "Created", value: service.createdAgo)
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
        .background(AppColors.background)
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
