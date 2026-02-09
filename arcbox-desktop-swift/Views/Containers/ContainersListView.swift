import SwiftUI

/// Center panel: list header + container rows + detail panel
struct ContainersListView: View {
    @State private var vm = ContainersViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left: list panel
            VStack(spacing: 0) {
                // Header bar (52pt height)
                containerListHeader

                // Container list or empty state
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
            .frame(width: vm.listWidth)

            // Resize handle
            ListResizeHandle(width: $vm.listWidth, min: 200, max: 500)

            // Right: detail panel
            ContainerDetailView(
                container: vm.selectedContainer,
                activeTab: $vm.activeTab
            )
        }
        .onAppear {
            vm.loadSampleData()
        }
        .sheet(isPresented: $vm.showNewContainerSheet) {
            NewContainerSheet()
        }
    }

    // MARK: - Header

    private var containerListHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Containers")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(vm.runningCount) running")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            HStack(spacing: 4) {
                IconButton(symbol: "plus") {
                    vm.showNewContainerSheet = true
                }
                IconButton(symbol: "magnifyingglass") {
                    // TODO: toggle search
                }
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
