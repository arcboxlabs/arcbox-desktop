import SwiftUI

/// Column 2: row-based machine list (matches ContainersListView pattern)
struct MachinesView: View {
    @Environment(MachinesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    @State private var pendingDeleteID: String?

    private var runningMachines: [MachineViewModel] {
        vm.filteredMachines.filter(\.isRunning)
    }

    private var stoppedMachines: [MachineViewModel] {
        vm.filteredMachines.filter { !$0.isRunning }
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.machines.isEmpty {
                emptyContent
            } else if vm.filteredMachines.isEmpty {
                ContentUnavailableView.search(text: vm.searchText)
            } else {
                machineList
            }
        }
        .background(AppColors.background)
        .navigationTitle("Machines")
        .navigationSubtitle("\(vm.runningCount) / \(vm.totalCount) running")
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(
                    action: { vm.showCreateSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .accessibilityLabel("New machine")
            }
        }
        .sheet(isPresented: Bindable(vm).showCreateSheet) {
            MachineCreateSheet()
        }
        .task(id: client != nil) {
            await vm.loadMachines(client: client)
        }
        .confirmationDialog(
            "Delete machine \(pendingDeleteID ?? "")?",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let id = pendingDeleteID else { return }
                pendingDeleteID = nil
                Task { await vm.deleteMachine(id, client: client) }
            }
        } message: {
            Text("This permanently deletes the machine and its data disk.")
        }
        .errorToast(message: Bindable(vm).lastError)
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch vm.loadState {
        case .waiting, .loading:
            VStack {
                Spacer()
                ProgressView("Loading machines…")
                    .progressViewStyle(.circular)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColors.textMuted)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Button("Retry") {
                    Task { await vm.loadMachines(client: client) }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        case .loaded:
            MachineEmptyState()
        }
    }

    private var machineList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Running machines
                ForEach(runningMachines) { machine in
                    MachineRowView(
                        machine: machine,
                        isSelected: vm.selectedID == machine.id,
                        onSelect: { vm.selectMachine(machine.id) },
                        onStartStop: {
                            Task { await vm.stopMachine(machine.id, client: client) }
                        },
                        onDelete: { pendingDeleteID = machine.id }
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
                            onStartStop: {
                                Task { await vm.startMachine(machine.id, client: client) }
                            },
                            onDelete: { pendingDeleteID = machine.id }
                        )
                    }
                }
            }
        }
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
