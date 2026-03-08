import SwiftUI

/// Column 2: row-based machine list (matches ContainersListView pattern)
struct MachinesView: View {
    @Environment(MachinesViewModel.self) private var vm

    private var runningMachines: [MachineViewModel] {
        vm.machines.filter(\.isRunning)
    }

    private var stoppedMachines: [MachineViewModel] {
        vm.machines.filter { !$0.isRunning }
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.machines.isEmpty {
                MachineEmptyState()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Running machines
                        ForEach(runningMachines) { machine in
                            MachineRowView(
                                machine: machine,
                                isSelected: vm.selectedID == machine.id,
                                onSelect: { vm.selectMachine(machine.id) },
                                onStartStop: { vm.stopMachine(machine.id) },
                                onDelete: { vm.deleteMachine(machine.id) }
                            )
                        }

                        // Stopped section
                        if !stoppedMachines.isEmpty {
                            sectionHeader("Stopped")
                            ForEach(stoppedMachines) { machine in
                                MachineRowView(
                                    machine: machine,
                                    isSelected: vm.selectedID == machine.id,
                                    onSelect: { vm.selectMachine(machine.id) },
                                    onStartStop: { vm.startMachine(machine.id) },
                                    onDelete: { vm.deleteMachine(machine.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle("Machines")
        .navigationSubtitle("\(vm.runningCount) / \(vm.totalCount) running")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {}) {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { vm.loadSampleData() }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
