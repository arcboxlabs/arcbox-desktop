import ArcBoxClient
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM

    // Shared ViewModels (injected from ArcBoxApp, shared with menu bar)
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(VolumesViewModel.self) private var volumesVM
    @Environment(ImagesViewModel.self) private var imagesVM
    @Environment(NetworksViewModel.self) private var networksVM

    // Feature ViewModels -- local to main window
    @State private var activityVM = ActivityViewModel()
    @State private var k8sState = KubernetesState()
    @State private var podsVM = PodsViewModel()
    @State private var servicesVM = ServicesViewModel()
    @State private var machinesVM = MachinesViewModel()
    @State private var sandboxesVM = SandboxesViewModel()
    @State private var templatesVM = TemplatesViewModel()
    @State private var runnersVM = RunnersViewModel()

    @State private var lastValidNav: NavItem? = .containers

    var body: some View {
        @Bindable var vm = appVM

        NavigationSplitView {
            sidebar
        } content: {
            // Always render `contentColumn` and vary only the numeric width
            // through the SAME flexible overload. Mixing the fixed
            // `navigationSplitViewColumnWidth(0)` overload with the flexible
            // `(min:ideal:max:)` one across sibling branches makes the column
            // width latch near 0 on navigation, collapsing the list content to
            // one-character-per-line text (Activity/Templates collapse to 0).
            contentColumn
                .background(AppColors.background)
                .navigationSplitViewColumnWidth(
                    min: isContentColumnCollapsed ? 0 : 150,
                    ideal: isContentColumnCollapsed ? 0 : 320,
                    max: isContentColumnCollapsed ? 0 : 600
                )
        } detail: {
            detailPanel
                .background(AppColors.sidebar)
        }
        .onChange(of: appVM.currentNav) { _, newNav in
            guard let newNav else { return }
            if newNav.isComingSoon {
                showComingSoonPanel()
                appVM.currentNav = lastValidNav
            } else {
                lastValidNav = newNav
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        @Bindable var vm = appVM

        return List(selection: $vm.currentNav) {
            Section("System") {
                ForEach(NavItem.Section.system.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Docker") {
                ForEach(NavItem.Section.docker.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Kubernetes") {
                ForEach(NavItem.Section.kubernetes.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Linux") {
                ForEach(NavItem.Section.linux.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("Sandbox") {
                ForEach(NavItem.Section.sandbox.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .tag(item)
                }
            }
            Section("CI Runners") {
                ForEach(NavItem.Section.runners.items) { item in
                    Label(item.label, systemImage: item.sfSymbol)
                        .badge(runnersVM.activeJobCount)
                        .tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarAccountButton()
        }
        .navigationSplitViewColumnWidth(180)
    }

    /// Sections rendered full-width in the detail column collapse the content
    /// column to zero width instead of showing a list.
    private var isContentColumnCollapsed: Bool {
        appVM.currentNav == .activity || appVM.currentNav == .templates
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch appVM.currentNav {
        case .activity:
            // Rendered full-width in the detail column; content column collapses.
            Color.clear
                .navigationTitle("Activity")
        case .containers:
            ContainersListView()
                .environment(containersVM)
        case .volumes:
            VolumesListView()
                .environment(volumesVM)
        case .images:
            ImagesListView()
                .environment(imagesVM)
        case .networks:
            NetworksListView()
                .environment(networksVM)
        case .pods:
            PodsListView()
                .environment(k8sState)
                .environment(podsVM)
        case .services:
            ServicesListView()
                .environment(k8sState)
                .environment(servicesVM)
        case .machines:
            MachinesView()
                .environment(machinesVM)
        case .runner:
            RunnersView()
                .environment(runnersVM)
        case .sandboxes:
            SandboxesListView()
                .environment(sandboxesVM)
        case .templates:
            // Rendered full-width in the detail column; content column collapses.
            Color.clear
                .navigationTitle("Templates")
        case nil:
            ContainersListView()
                .environment(containersVM)
        }
    }

    // MARK: - Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        switch appVM.currentNav {
        case .activity:
            ActivityView()
                .environment(activityVM)
        case .containers:
            ContainerDetailView()
                .environment(containersVM)
        case .volumes:
            VolumeDetailView()
                .environment(volumesVM)
        case .images:
            ImageDetailView()
                .environment(imagesVM)
        case .networks:
            NetworkDetailView()
                .environment(networksVM)
                .environment(containersVM)
        case .pods:
            PodDetailView()
                .environment(k8sState)
                .environment(podsVM)
        case .services:
            ServiceDetailView()
                .environment(k8sState)
                .environment(servicesVM)
        case .machines:
            MachineDetailView()
                .environment(machinesVM)
        case .runner:
            // Job / host detail arrives with RUN-12 / RUN-13.
            DetailPlaceholderView()
        case .sandboxes:
            SandboxDetailView()
                .environment(sandboxesVM)
        case .templates:
            TemplatesListView()
                .environment(templatesVM)
        case nil:
            ContainerDetailView()
                .environment(containersVM)
        }
    }

}

/// Placeholder shown when no detail is available (e.g. Machines)
struct DetailPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textMuted)
            Text("No Selection")
                .foregroundStyle(AppColors.textSecondary)
                .font(.system(size: 15))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
        .environment(ContainersViewModel())
        .environment(ImagesViewModel())
        .environment(NetworksViewModel())
        .environment(VolumesViewModel())
}
