import SwiftUI

/// Column 3: pod detail with tab-based toolbar
struct PodDetailView: View {
    @Environment(PodsViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let pod = vm.selectedPod

        VStack(spacing: 0) {
            if let pod {
                switch vm.activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "Name", value: pod.name)
                            InfoRow(label: "Namespace", value: pod.namespace)
                            InfoRow(label: "Phase", value: pod.phase.rawValue)
                            InfoRow(label: "Ready", value: pod.readyDisplay)
                            InfoRow(label: "Restarts", value: "\(pod.restartCount)")
                            InfoRow(label: "Created", value: pod.createdAgo)
                        }
                        .infoSectionStyle()
                        .padding(16)
                    }
                case .logs:
                    Spacer()
                    Text("Logs coming soon...")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                case .terminal:
                    Spacer()
                    Text("Terminal coming soon...")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
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
                    ForEach(PodDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)
            }
        }
    }
}
