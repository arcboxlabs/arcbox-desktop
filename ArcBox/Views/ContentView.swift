import ArcBoxClient
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM

    // Shared ViewModels (injected from ArcBoxApp, shared with menu bar)
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(VolumesViewModel.self) private var volumesVM
    @Environment(ImagesViewModel.self) private var imagesVM
    @Environment(NetworksViewModel.self) private var networksVM

    // Feature ViewModels – local to main window
    @State private var podsVM = PodsViewModel()
    @State private var servicesVM = ServicesViewModel()
    @State private var machinesVM = MachinesViewModel()
    @State private var sandboxesVM = SandboxesViewModel()
    @State private var templatesVM = TemplatesViewModel()

    @State private var lastValidNav: NavItem? = .containers

    var body: some View {
        @Bindable var vm = appVM

        NavigationSplitView {
            List(selection: $vm.currentNav) {
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
            .navigationSplitViewColumnWidth(180)
        } content: {
            // Sandbox section: collapse content column, full view goes to detail
            if isSandboxSection {
                Color.clear
                    .navigationSplitViewColumnWidth(0)
                    .navigationTitle(appVM.currentNav == .templates ? "Templates" : "Sandboxes")
            } else {
                contentColumn
                    .navigationSplitViewColumnWidth(min: 150, ideal: 280, max: 600)
            }
        } detail: {
            detailColumn
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

    private var isSandboxSection: Bool {
        appVM.currentNav == .sandboxes || appVM.currentNav == .templates
    }

    // MARK: - Content column

    @ViewBuilder
    private var contentColumn: some View {
        switch appVM.currentNav {
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
                .environment(podsVM)
        case .services:
            ServicesListView()
                .environment(servicesVM)
        case .machines:
            MachinesView()
                .environment(machinesVM)
        case .sandboxes, .templates:
            // Handled in detail column
            Color.clear
        case nil:
            ContainersListView()
                .environment(containersVM)
        }
    }

    // MARK: - Detail column

    @ViewBuilder
    private var detailColumn: some View {
        switch appVM.currentNav {
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
                .environment(podsVM)
        case .services:
            ServiceDetailView()
                .environment(servicesVM)
        case .machines:
            MachineDetailView()
                .environment(machinesVM)
        case .sandboxes:
            SandboxesListView()
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
        Text("No Selection")
            .foregroundStyle(AppColors.textSecondary)
            .font(.system(size: 15))
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
