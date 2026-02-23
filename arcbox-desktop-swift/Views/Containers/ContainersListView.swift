import SwiftUI

/// Column 2: container list with toolbar
struct ContainersListView: View {
    @Environment(ContainersViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            if vm.containers.isEmpty {
                ContainerEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Compose groups
                        ForEach(vm.composeGroups, id: \.project) { group in
                            ContainerGroupView(
                                project: group.project,
                                containers: group.containers,
                                isExpanded: vm.isGroupExpanded(group.project),
                                selectedID: vm.selectedID,
                                onToggle: { vm.toggleGroup(group.project) },
                                onSelect: { vm.selectContainer($0) },
                                onStartStop: { id, running in
                                    if running { vm.stopContainer(id) }
                                    else { vm.startContainer(id) }
                                },
                                onDelete: { vm.removeContainer($0) }
                            )
                        }

                        // Standalone containers
                        ForEach(vm.standaloneContainers) { container in
                            ContainerRowView(
                                container: container,
                                isSelected: vm.selectedID == container.id,
                                indented: false,
                                onSelect: { vm.selectContainer(container.id) },
                                onStartStop: {
                                    if container.isRunning { vm.stopContainer(container.id) }
                                    else { vm.startContainer(container.id) }
                                },
                                onDelete: { vm.removeContainer(container.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Containers")
        .navigationSubtitle("\(vm.runningCount) running")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
                Button(action: { vm.showNewContainerSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            vm.loadSampleData()
        }
        .sheet(isPresented: Bindable(vm).showNewContainerSheet) {
            NewContainerSheet()
        }
    }
}
