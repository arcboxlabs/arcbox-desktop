import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) private var appVM

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            settingsContent
                .navigationTitle(appVM.settingsTab?.rawValue ?? "")
        }
        .frame(minWidth: 700, minHeight: 580)
    }

    private var sidebar: some View {
        @Bindable var vm = appVM

        return List(SettingsTab.allCases, selection: $vm.settingsTab) { tab in
            Label(tab.rawValue, systemImage: tab.sfSymbol)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Settings navigation")
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
        case .storage:
            StorageSettingsView()
        case nil:
            EmptyView()
        }
    }
}
