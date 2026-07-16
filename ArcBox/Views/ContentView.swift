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

    @State private var lastValidNav: NavItem? = .containers

    var body: some View {
        @Bindable var vm = appVM

        NavigationSplitView {
            sidebar
        } content: {
            if isTemplatesSection {
                Color.clear
                    .navigationSplitViewColumnWidth(0)
                    .navigationTitle("Templates")
            } else if appVM.currentNav == .activity {
                // Activity is a single full-width dashboard rendered in the
                // detail column; collapse the content column.
                Color.clear
                    .navigationSplitViewColumnWidth(0)
                    .navigationTitle("Activity")
            } else {
                contentColumn
                    .background(AppColors.background)
                    .navigationSplitViewColumnWidth(min: 150, ideal: 320, max: 600)
            }
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
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarAccountButton()
        }
        .navigationSplitViewColumnWidth(180)
    }

    private var isTemplatesSection: Bool {
        appVM.currentNav == .templates
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch appVM.currentNav {
        case .activity:
            // Rendered full-width in the detail column.
            Color.clear
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
        case .sandboxes:
            SandboxesListView()
                .environment(sandboxesVM)
        case .templates:
            // Handled in detail column
            Color.clear
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
