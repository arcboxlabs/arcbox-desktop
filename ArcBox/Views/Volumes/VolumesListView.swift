import SwiftUI
import ArcBoxClient
import DockerClient

/// Column 2: volumes list with toolbar
struct VolumesListView: View {
    @Environment(VolumesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.dockerClient) private var docker

    var body: some View {
        VStack(spacing: 0) {
            // "In Use" section header
            HStack {
                Text("In Use")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let orchestrator, !orchestrator.isReady {
                StartupProgressView(orchestrator: orchestrator)
            } else if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else if vm.volumes.isEmpty {
                VolumeEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.sortedVolumes) { volume in
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
                Button(action: { vm.showNewVolumeSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: Bindable(vm).showNewVolumeSheet) {
            NewVolumeSheet()
        }
        .task(id: docker != nil) { await vm.loadVolumes(docker: docker) }
        .onReceive(NotificationCenter.default.publisher(for: .dockerVolumeChanged)) { _ in
            Task { await vm.loadVolumes(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await vm.loadVolumes(docker: docker) }
        }
    }
}
