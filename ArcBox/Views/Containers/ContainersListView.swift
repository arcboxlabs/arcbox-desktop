import ArcBoxClient
import DockerClient
import SwiftUI

/// Column 2: container list with toolbar.
///
/// The body decides only which content fills the column. Everything that
/// reads hot view-model state — the subtitle's running count, the search
/// bindings — lives in modifiers with their own dependency tracking, so a
/// container state flip re-evaluates those and not this body, the toolbar it
/// declares, or the `NSViewControllerRepresentable` under it.
struct ContainersListView: View {
    @Environment(ContainersViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.arcboxClient) private var client
    @Environment(\.dockerClient) private var docker

    #if DEBUG
        /// Body evaluations since launch; tests read it to pin what invalidates
        /// this view.
        static var bodyEvaluations = 0
    #endif

    var body: some View {
        #if DEBUG
            Self.bodyEvaluations += 1
        #endif
        return
            content
            .navigationTitle("Containers")
            .modifier(ContainersListSubtitle(dockerAvailable: docker != nil))
            .modifier(ContainersListSearch())
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                        .disabled(!dockerActionsAvailable)
                    Button(
                        action: { vm.showNewContainerSheet = true },
                        label: {
                            Image(systemName: "plus")
                        }
                    )
                    .accessibilityLabel("New container")
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!dockerActionsAvailable)
                }
            }
            .task(id: daemonManager.setupPhase.isDockerReady && docker != nil) {
                guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
                await vm.loadContainersFromDocker(docker: docker, iconClient: client)
            }
            .onReceive(NotificationCenter.default.publisher(for: .dockerContainerChanged)) { _ in
                guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
                Task { await vm.loadContainersFromDocker(docker: docker, iconClient: client) }
            }
            .sheet(isPresented: Bindable(vm).showNewContainerSheet) {
                NewContainerSheet()
            }
            .listErrorToast(
                operationError: Bindable(vm).lastError,
                refreshError: Bindable(vm).refreshError,
                resourceName: "containers"
            )
    }

    @ViewBuilder
    private var content: some View {
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
                ContainersListControllerView(
                    viewModel: vm,
                    loadingTitle: "Loading containers…",
                    useDNS: daemonManager.dnsResolverInstalled
                        && daemonManager.routeInstalled,
                    onRetry: {
                        Task {
                            await vm.loadContainersFromDocker(
                                docker: docker,
                                iconClient: client
                            )
                        }
                    },
                    onSelect: { id in
                        Task {
                            guard vm.containers.contains(where: { $0.id == id }) else {
                                return
                            }
                            await vm.selectContainer(id, client: client, docker: docker)
                        }
                    },
                    onToggle: { id in
                        Task {
                            guard
                                let container = vm.containers.first(where: { $0.id == id }),
                                !container.isTransitioning
                            else {
                                return
                            }
                            if container.isRunning {
                                await vm.stopContainerDocker(id, docker: docker)
                            } else {
                                await vm.startContainerDocker(id, docker: docker)
                            }
                        }
                    },
                    onDelete: { id in
                        Task {
                            guard
                                let container = vm.containers.first(where: { $0.id == id }),
                                !container.isTransitioning
                            else {
                                return
                            }
                            await vm.removeContainerDocker(id, docker: docker)
                        }
                    },
                    onToggleGroup: { project, ids in
                        Task {
                            let containers = ids.compactMap { id in
                                vm.containers.first { $0.id == id }
                            }
                            guard
                                containers.count == ids.count,
                                containers.allSatisfy { $0.composeProject == project },
                                !containers.contains(where: \.isTransitioning)
                            else {
                                return
                            }
                            if containers.contains(where: \.isRunning) {
                                await vm.stopContainersDocker(ids, docker: docker)
                            } else {
                                await vm.startContainersDocker(ids, docker: docker)
                            }
                        }
                    },
                    onDeleteGroup: { project, ids in
                        Task {
                            let containers = ids.compactMap { id in
                                vm.containers.first { $0.id == id }
                            }
                            guard
                                containers.count == ids.count,
                                containers.allSatisfy { $0.composeProject == project },
                                !containers.contains(where: \.isTransitioning)
                            else {
                                return
                            }
                            await vm.removeContainersDocker(ids, docker: docker)
                        }
                    }
                )
            }
        }
    }

    private var dockerActionsAvailable: Bool {
        (orchestrator?.isReady ?? true)
            && daemonManager.state.isRunning
            && daemonManager.setupPhase.isDockerReady
            && docker != nil
    }
}

/// The navigation subtitle, kept out of `ContainersListView.body` because its
/// running count depends on `containers`, which changes on every Docker event.
private struct ContainersListSubtitle: ViewModifier {
    @Environment(ContainersViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    let dockerAvailable: Bool

    func body(content: Content) -> some View {
        content.navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        if let orchestrator, !orchestrator.isReady {
            return "Starting…"
        }
        guard daemonManager.state.isRunning else {
            return "Unavailable"
        }
        guard daemonManager.setupPhase.isDockerReady else {
            return "Starting…"
        }
        guard dockerAvailable else {
            return "Unavailable"
        }
        return switch vm.loadState {
        case .waiting, .loading:
            "Loading…"
        case .failed:
            "Unavailable"
        case .loaded:
            "\(vm.runningCount) running"
        }
    }
}

private struct ContainersListSearch: ViewModifier {
    @Environment(ContainersViewModel.self) private var vm

    func body(content: Content) -> some View {
        content
            .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
            .onChange(of: vm.isSearching) { _, newValue in
                if !newValue { vm.searchText = "" }
            }
    }
}

private struct ContainersListControllerView: NSViewControllerRepresentable {
    let viewModel: ContainersViewModel
    let loadingTitle: String
    let useDNS: Bool
    let onRetry: @MainActor () -> Void
    let onSelect: @MainActor (String) -> Void
    let onToggle: @MainActor (String) -> Void
    let onDelete: @MainActor (String) -> Void
    let onToggleGroup: @MainActor (String, [String]) -> Void
    let onDeleteGroup: @MainActor (String, [String]) -> Void

    func makeNSViewController(context _: Context) -> ContainersListViewController {
        ContainersListViewController(
            viewModel: viewModel,
            loadingTitle: loadingTitle,
            useDNS: useDNS,
            actions: actions
        )
    }

    func updateNSViewController(
        _ controller: ContainersListViewController,
        context _: Context
    ) {
        controller.update(
            loadingTitle: loadingTitle,
            useDNS: useDNS,
            actions: actions
        )
    }

    private var actions: ContainersListViewController.Actions {
        .init(
            retry: onRetry,
            select: onSelect,
            toggle: onToggle,
            delete: onDelete,
            toggleGroup: onToggleGroup,
            deleteGroup: onDeleteGroup
        )
    }
}
