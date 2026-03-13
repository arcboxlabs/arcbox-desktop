import SwiftUI

/// Column 2: services list with toolbar
struct ServicesListView: View {
    @Environment(ServicesViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            if !vm.kubernetesEnabled {
                KubernetesDisabledView()
            } else if vm.services.isEmpty {
                VStack {
                    Spacer()
                    Text("No services")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.services) { service in
                            ServiceRowView(
                                service: service,
                                isSelected: vm.selectedID == service.id,
                                onSelect: { vm.selectService(service.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Services")
        .navigationSubtitle(vm.kubernetesEnabled ? "\(vm.serviceCount) total" : "Disabled")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .onAppear { vm.loadSampleData() }
    }
}
