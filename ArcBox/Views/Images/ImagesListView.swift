import ArcBoxClient
import DockerClient
import SwiftUI

/// Column 2: images list with toolbar
struct ImagesListView: View {
    @Environment(ImagesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.arcboxClient) private var client
    @Environment(\.dockerClient) private var docker

    var body: some View {
        VStack(spacing: 0) {
            if let orchestrator, !orchestrator.isReady {
                StartupProgressView(orchestrator: orchestrator)
            } else if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else if vm.images.isEmpty {
                ImageEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !inUseImages.isEmpty {
                            sectionHeader("In Use")
                            ForEach(inUseImages) { image in
                                imageRow(image)
                            }
                        }
                        if !unusedImages.isEmpty {
                            sectionHeader("Unused")
                            ForEach(unusedImages) { image in
                                imageRow(image)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Images")
        .navigationSubtitle(vm.totalSize)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: { vm.showPullImageSheet = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Pull image")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: Bindable(vm).showPullImageSheet) {
            PullImageSheet()
        }
        .errorToast(message: Bindable(vm).lastError)
        .task(id: docker != nil) { await vm.loadImages(docker: docker, iconClient: client) }
        .onReceive(NotificationCenter.default.publisher(for: .dockerImageChanged)) { _ in
            Task { await vm.loadImages(docker: docker, iconClient: client) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await vm.loadImages(docker: docker, iconClient: client) }
        }
    }

    private var inUseImages: [ImageViewModel] {
        vm.sortedImages.filter(\.inUse)
    }

    private var unusedImages: [ImageViewModel] {
        vm.sortedImages.filter { !$0.inUse }
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
    private func imageRow(_ image: ImageViewModel) -> some View {
        ImageRowView(
            image: image,
            isSelected: vm.selectedID == image.id,
            onSelect: { vm.selectImage(image.id) },
            onDelete: {
                Task { await vm.removeImage(image.id, dockerId: image.dockerId, docker: docker) }
            }
        )
    }
}
