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
                            InfoRow(label: "Name", value: pod.name, rowIndex: 0)
                            InfoRow(label: "Namespace", value: pod.namespace, rowIndex: 1)
                            InfoRow(label: "Phase", value: pod.phase.rawValue, rowIndex: 2)
                            InfoRow(label: "Ready", value: pod.readyDisplay, rowIndex: 3)
                            InfoRow(label: "Restarts", value: "\(pod.restartCount)", rowIndex: 4)
                            InfoRow(label: "Created", value: pod.createdAgo, rowIndex: 5)
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
