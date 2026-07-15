import SwiftUI

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case account = "Account"
    case system = "System"
    case fleet = "Fleet"
    // TODO: Implement network settings (ABXD-88)
    // case network = "Network"
    case storage = "Storage"
    // TODO: Implement machines/docker/kubernetes tabs (ABXD-86)
    // case machines = "Machines"
    // case docker = "Docker"
    // case kubernetes = "Kubernetes"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "person.circle"
        case .system: return "square.grid.2x2"
        case .fleet: return "server.rack"
        // case .network: return "globe"
        case .storage: return "externaldrive"
        // case .machines: return "desktopcomputer"
        // case .docker: return "shippingbox"
        // case .kubernetes: return "helm"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            settingsContent
                .navigationTitle(appVM.settingsTab?.rawValue ?? "")
                .background(AppColors.background)
        }
        .frame(minWidth: 700, minHeight: 580)
        .background(AppColors.background)
    }

    private var sidebar: some View {
        @Bindable var vm = appVM

        return ZStack {
            AppColors.sidebar
                .ignoresSafeArea(.container, edges: [.top, .bottom, .leading])

            List(SettingsTab.allCases, selection: $vm.settingsTab) { tab in
                Label(tab.rawValue, systemImage: tab.sfSymbol)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .background(AppColors.sidebar)
        .navigationSplitViewColumnWidth(180)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch appVM.settingsTab {
        case .general:
            GeneralSettingsView()
        case .account:
            AccountSettingsView()
        case .system:
            SystemSettingsView()
        case .fleet:
            FleetSettingsView()
        // TODO: Implement network settings (ABXD-88)
        // case .network:
        //     NetworkSettingsView()
        case .storage:
            StorageSettingsView()
        case nil:
            EmptyView()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppViewModel())
}
