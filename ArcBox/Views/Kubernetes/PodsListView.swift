import ArcBoxClient
import SwiftUI

/// Column 2: pods list with toolbar
struct PodsListView: View {
    @Environment(KubernetesState.self) private var k8s
    @Environment(PodsViewModel.self) private var vm
    @Environment(\.arcboxClient) private var arcboxClient

    var body: some View {
        VStack(spacing: 0) {
            if !k8s.enabled {
                KubernetesDisabledView(isStarting: k8s.isStarting) {
                    Task {
                        await k8s.start(client: arcboxClient)
                        await loadPodsUntilReady()
                    }
                }
            } else if vm.pods.isEmpty {
                VStack {
                    Spacer()
                    if vm.isLoading {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Text("No pods")
                            .foregroundStyle(AppColors.textSecondary)
                    }
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
        .navigationSubtitle(k8s.enabled ? "\(vm.podCount) total" : "Disabled")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { k8s.enabled || k8s.isStarting },
                    set: { newValue in
                        Task {
                            if newValue {
                                await k8s.start(client: arcboxClient)
                                await loadPodsUntilReady()
                            } else {
                                await k8s.stop(client: arcboxClient)
                            }
                        }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .disabled(k8s.isStarting || k8s.isStopping)

                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .task {
            await k8s.checkStatus(client: arcboxClient)
            if k8s.enabled {
                await loadPodsUntilReady()
            }
        }
        .onChange(of: k8s.enabled) { _, enabled in
            if !enabled { vm.clear() }
        }
    }

    /// Retry loading pods until the request succeeds or timeout (~30s).
    private func loadPodsUntilReady() async {
        for attempt in 0..<15 {
            if Task.isCancelled { return }
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
            let success = await vm.loadPods(client: arcboxClient)
            if success { return }
        }
    }
}
