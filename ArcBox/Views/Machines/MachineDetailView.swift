import SwiftUI

/// Column 3: machine detail with tab-based toolbar (matches ContainerDetailView pattern)
struct MachineDetailView: View {
    @Environment(MachinesViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let machine = vm.selectedMachine

        VStack(spacing: 0) {
            if let machine {
                switch vm.activeTab {
                case .info:
                    MachineInfoTab(machine: machine)
                case .logs:
                    MachineLogsTab(machine: machine)
                case .terminal:
                    MachineTerminalTab(machine: machine)
                case .files:
                    MachineFilesTab(machine: machine)
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
                    ForEach(MachineDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
        }
    }
}
