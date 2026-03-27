import SwiftUI

/// Column 3: sandbox detail with tab-based toolbar
struct SandboxDetailView: View {
    @Environment(SandboxesViewModel.self) private var vm

    private func stateColor(_ state: SandboxState) -> Color {
        switch state {
        case .running: AppColors.running
        case .paused: AppColors.warning
        case .stopped: AppColors.stopped
        }
    }

    var body: some View {
        @Bindable var vm = vm
        let sandbox = vm.selectedSandbox

        VStack(spacing: 0) {
            if let sandbox {
                switch vm.activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "Alias", value: sandbox.alias)
                            InfoRow(label: "ID", value: sandbox.shortID)
                            InfoRow(label: "Template", value: sandbox.templateID)
                            InfoRow(label: "Status", value: sandbox.state.label)
                            InfoRow(label: "CPU", value: sandbox.cpuDisplay)
                            InfoRow(label: "Memory", value: sandbox.memoryDisplay)
                            InfoRow(label: "Started", value: sandbox.startedAgo)
                            InfoRow(label: "Time Left", value: sandbox.timeRemaining)
                        }
                        .infoSectionStyle()
                        .padding(16)
                    }
                case .logs:
                    Spacer()
                    Text("Logs coming soon...")
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
                    ForEach(SandboxDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
    }
}
