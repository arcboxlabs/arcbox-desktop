import SwiftUI
import ArcBoxClient
import DockerClient

/// Column 2: container list with toolbar
struct ContainersListView: View {
    @Environment(ContainersViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client
    @Environment(\.dockerClient) private var docker

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
                                    Task {
                                        if running { await vm.stopContainerDocker(id, docker: docker) }
                                        else { await vm.startContainerDocker(id, docker: docker) }
                                    }
                                },
                                onDelete: { id in
                                    Task { await vm.removeContainerDocker(id, docker: docker) }
                                }
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
                                    Task {
                                        if container.isRunning { await vm.stopContainerDocker(container.id, docker: docker) }
                                        else { await vm.startContainerDocker(container.id, docker: docker) }
                                    }
                                },
                                onDelete: {
                                    Task { await vm.removeContainerDocker(container.id, docker: docker) }
                                }
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
        .task {
            await vm.loadContainersFromDocker(docker: docker)
        }
        .sheet(isPresented: Bindable(vm).showNewContainerSheet) {
            NewContainerSheet()
        }
    }
}
