import ArcBoxClient
import DockerClient
import SwiftUI

/// Column 2: volumes list with toolbar
struct VolumesListView: View {
    @Environment(VolumesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.dockerClient) private var docker

    var body: some View {
        VStack(spacing: 0) {
            if let orchestrator, !orchestrator.isReady {
                StartupProgressView(orchestrator: orchestrator)
            } else if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else if vm.volumes.isEmpty {
                VolumeEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !inUseVolumes.isEmpty {
                            sectionHeader("In Use")
                            ForEach(inUseVolumes) { volume in
                                volumeRow(volume)
                            }
                        }
                        if !unusedVolumes.isEmpty {
                            sectionHeader("Unused")
                            ForEach(unusedVolumes) { volume in
                                volumeRow(volume)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Volumes")
        .navigationSubtitle(vm.totalSize)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(
                    action: { vm.showNewVolumeSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .accessibilityLabel("New volume")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: Bindable(vm).showNewVolumeSheet) {
            NewVolumeSheet()
        }
        .errorToast(message: Bindable(vm).lastError)
        .task(id: daemonManager.dockerSocketLinked) {
            guard daemonManager.dockerSocketLinked else { return }
            await vm.loadVolumes(docker: docker)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerVolumeChanged)) { _ in
            Task { await vm.loadVolumes(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await vm.loadVolumes(docker: docker) }
        }
    }

    private var inUseVolumes: [VolumeViewModel] {
        vm.sortedVolumes.filter(\.inUse)
    }

    private var unusedVolumes: [VolumeViewModel] {
        vm.sortedVolumes.filter { !$0.inUse }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func volumeRow(_ volume: VolumeViewModel) -> some View {
        VolumeRowView(
            volume: volume,
            isSelected: vm.selectedID == volume.id,
            onSelect: { vm.selectVolume(volume.id) },
            onDelete: {
                Task { await vm.removeVolume(volume.name, docker: docker) }
            }
        )
    }
}
