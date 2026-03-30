import ArcBoxClient
import SwiftUI

/// Column 2: services list with toolbar
struct ServicesListView: View {
    @Environment(KubernetesState.self) private var k8s
    @Environment(ServicesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var arcboxClient

    var body: some View {
        VStack(spacing: 0) {
            if !k8s.enabled {
                KubernetesDisabledView(isStarting: k8s.isStarting) {
                    Task {
                        if !k8s.enabled {
                            await k8s.start(client: arcboxClient)
                        }
                        await loadServicesUntilReady()
                    }
                }
            } else if vm.services.isEmpty {
                VStack {
                    Spacer()
                    if vm.isLoading {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Text("No services")
                            .foregroundStyle(AppColors.textSecondary)
                    }
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
        .navigationSubtitle(k8s.enabled ? "\(vm.serviceCount) total" : "Disabled")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .task {
            await k8s.checkStatus(client: arcboxClient)
            if k8s.enabled {
                await loadServicesUntilReady()
            }
        }
    }

    /// Retry loading services until the request succeeds or timeout (~30s).
    private func loadServicesUntilReady() async {
        for attempt in 0..<15 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(2))
            }
            let success = await vm.loadServices(client: arcboxClient)
            if success { return }
        }
    }
}
