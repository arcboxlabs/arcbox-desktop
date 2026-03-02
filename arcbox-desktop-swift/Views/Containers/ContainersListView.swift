import SwiftUI
import ArcBoxClient
import DockerClient

/// Column 2: container list with toolbar
struct ContainersListView: View {
    @Environment(ContainersViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client
    @Environment(\.dockerClient) private var docker

    /// Compose groups with at least one running container
    private var activeComposeGroups: [(project: String, containers: [ContainerViewModel])] {
        vm.composeGroups.filter { $0.containers.contains(where: \.isRunning) }
    }

    /// Compose groups where all containers are stopped
    private var stoppedComposeGroups: [(project: String, containers: [ContainerViewModel])] {
        vm.composeGroups.filter { !$0.containers.contains(where: \.isRunning) }
    }

    private var runningStandaloneContainers: [ContainerViewModel] {
        vm.standaloneContainers.filter(\.isRunning)
    }

    private var stoppedStandaloneContainers: [ContainerViewModel] {
        vm.standaloneContainers.filter { !$0.isRunning }
    }

    private var hasStoppedContent: Bool {
        !stoppedComposeGroups.isEmpty || !stoppedStandaloneContainers.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if vm.containers.isEmpty {
                ContainerEmptyState()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Active compose groups (has running containers)
                        composeGroupRows(for: activeComposeGroups)

                        // Running standalone containers
                        standaloneRows(for: runningStandaloneContainers)

                        // Stopped section
                        if hasStoppedContent {
                            sectionHeader("Stopped")
                            composeGroupRows(for: stoppedComposeGroups)
                            standaloneRows(for: stoppedStandaloneContainers)
                        }
                    }
                }
            }
        }
        .navigationTitle("Containers")
        .navigationSubtitle("\(vm.runningCount) running")
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: { vm.showNewContainerSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await vm.loadContainersFromDocker(docker: docker)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await vm.loadContainersFromDocker(docker: docker) }
        }
        .sheet(isPresented: Bindable(vm).showNewContainerSheet) {
            NewContainerSheet()
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

    @ViewBuilder
    private func composeGroupRows(for groups: [(project: String, containers: [ContainerViewModel])]) -> some View {
        ForEach(groups, id: \.project) { group in
            ContainerGroupView(
                project: group.project,
                containers: group.containers,
                isExpanded: vm.isGroupExpanded(group.project),
                selectedID: vm.selectedID,
                onToggle: { vm.toggleGroup(group.project) },
                onSelect: { id in
                    Task {
                        await vm.selectContainer(id, client: client, docker: docker)
                    }
                },
                onStartStop: { id, running in
                    Task {
                        if running { await vm.stopContainerDocker(id, docker: docker) }
                        else { await vm.startContainerDocker(id, docker: docker) }
                    }
                },
                onDelete: { id in
                    Task { await vm.removeContainerDocker(id, docker: docker) }
                },
                onStartStopAll: { ids, running in
                    Task {
                        if running {
                            await vm.stopContainersDocker(ids, docker: docker)
                        } else {
                            await vm.startContainersDocker(ids, docker: docker)
                        }
                    }
                },
                onDeleteAll: { ids in
                    Task {
                        await vm.removeContainersDocker(ids, docker: docker)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func standaloneRows(for containers: [ContainerViewModel]) -> some View {
        ForEach(containers) { container in
            ContainerRowView(
                container: container,
                isSelected: vm.selectedID == container.id,
                indented: false,
                onSelect: {
                    Task {
                        await vm.selectContainer(container.id, client: client, docker: docker)
                    }
                },
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
