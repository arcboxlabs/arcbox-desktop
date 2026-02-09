import SwiftUI

/// Card-based machine layout (full-width, no list/detail split)
struct MachinesView: View {
    @State private var vm = MachinesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Text("Machines")
                        .font(.system(size: 13, weight: .semibold))

                    Text("\(vm.runningCount) / \(vm.totalCount) running")
                        .badgeStyle()
                }

                Spacer()

                Button(action: {}) {
                    Text("+ New Machine")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(height: 52)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) { Divider() }

            // Machine list
            ScrollView {
                if vm.machines.isEmpty {
                    MachineEmptyState()
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(vm.machines) { machine in
                            MachineCardView(
                                machine: machine,
                                isSelected: vm.selectedID == machine.id,
                                onSelect: { vm.selectMachine(machine.id) },
                                onStartStop: {
                                    if machine.isRunning { vm.stopMachine(machine.id) }
                                    else { vm.startMachine(machine.id) }
                                },
                                onDelete: { vm.deleteMachine(machine.id) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(AppColors.background)
        .onAppear { vm.loadSampleData() }
    }
}
