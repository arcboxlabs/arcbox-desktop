import ArcBoxClient
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM

    // Feature ViewModels – shared between content and detail columns
    @State private var containersVM = ContainersViewModel()
    @State private var volumesVM = VolumesViewModel()
    @State private var imagesVM = ImagesViewModel()
    @State private var networksVM = NetworksViewModel()
    @State private var podsVM = PodsViewModel()
    @State private var servicesVM = ServicesViewModel()
    @State private var machinesVM = MachinesViewModel()
    @State private var sandboxesVM = SandboxesViewModel()
    @State private var templatesVM = TemplatesViewModel()

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
}
