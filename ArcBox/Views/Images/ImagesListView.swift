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
            } else if !daemonManager.setupPhase.isDockerReady {
                ProgressView(daemonManager.setupMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if docker == nil {
                ContentUnavailableView {
                    Label("Docker Client Unavailable", systemImage: "shippingbox")
                } description: {
                    Text("ArcBox is running, but no Docker client is available.")
                }
            } else {
                ImagesListControllerView(
                    viewModel: vm,
                    loadingTitle: "Loading images…",
                    onRetry: {
                        Task { await vm.loadImages(docker: docker, iconClient: client) }
                    },
                    onDelete: { id in
                        guard let image = vm.images.first(where: { $0.id == id }) else {
                            return
                        }
                        Task {
                            await vm.removeImage(
                                image.id,
                                dockerId: image.dockerId,
                                docker: docker
                            )
                        }
                    }
                )
            }
        }
        .navigationTitle("Images")
        .navigationSubtitle(listSubtitle)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                    .disabled(!dockerActionsAvailable)
                Button(
                    action: { vm.showPullImageSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .accessibilityLabel("Pull image")
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!dockerActionsAvailable)
            }
        }
        .sheet(isPresented: Bindable(vm).showPullImageSheet) {
            PullImageSheet()
        }
        .listErrorToast(
            operationError: Bindable(vm).lastError,
            refreshError: Bindable(vm).refreshError,
            resourceName: "images"
        )
        .task(id: daemonManager.setupPhase.isDockerReady && docker != nil) {
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            await vm.loadImages(docker: docker, iconClient: client)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerImageChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            Task { await vm.loadImages(docker: docker, iconClient: client) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            Task { await vm.loadImages(docker: docker, iconClient: client) }
        }
    }

    private var dockerActionsAvailable: Bool {
        (orchestrator?.isReady ?? true)
            && daemonManager.state.isRunning
            && daemonManager.setupPhase.isDockerReady
            && docker != nil
    }

    private var listSubtitle: String {
        if let orchestrator, !orchestrator.isReady {
            return "Starting…"
        }
        guard daemonManager.state.isRunning else {
            return "Unavailable"
        }
        guard daemonManager.setupPhase.isDockerReady else {
            return "Starting…"
        }
        guard docker != nil else {
            return "Unavailable"
        }
        return switch vm.loadState {
        case .waiting, .loading:
            "Loading…"
        case .failed:
            "Unavailable"
        case .loaded:
            vm.totalSize
        }
    }
}

private struct ImagesListControllerView: NSViewControllerRepresentable {
    let viewModel: ImagesViewModel
    let loadingTitle: String
    let onRetry: @MainActor () -> Void
    let onDelete: @MainActor (String) -> Void

    func makeNSViewController(context _: Context) -> ImagesListViewController {
        ImagesListViewController(
            viewModel: viewModel,
            loadingTitle: loadingTitle,
            onRetry: onRetry,
            onDelete: onDelete
        )
    }

    func updateNSViewController(
        _ controller: ImagesListViewController,
        context _: Context
    ) {
        controller.update(
            loadingTitle: loadingTitle,
            onRetry: onRetry,
            onDelete: onDelete
        )
    }
}
