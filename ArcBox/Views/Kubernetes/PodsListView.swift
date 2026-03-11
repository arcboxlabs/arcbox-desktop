import SwiftUI

/// Column 2: pods list with toolbar
struct PodsListView: View {
    @Environment(PodsViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            if !vm.kubernetesEnabled {
                KubernetesDisabledView()
            } else if vm.pods.isEmpty {
                VStack {
                    Spacer()
                    Text("No pods")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.pods) { pod in
                            PodRowView(
                                pod: pod,
                                isSelected: vm.selectedID == pod.id,
                                onSelect: { vm.selectPod(pod.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Pods")
        .navigationSubtitle(vm.kubernetesEnabled ? "\(vm.podCount) total" : "Disabled")
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
