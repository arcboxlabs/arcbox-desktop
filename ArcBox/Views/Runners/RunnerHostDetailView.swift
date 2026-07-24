import SwiftUI

struct RunnerHostDetailView: View {
    let host: RunnerHostViewModel

    @Environment(RunnerPlatformStore.self) private var platformStore
    @Environment(RunnersViewModel.self) private var runners
    @State private var activeTab: RunnerHostDetailTab = .overview

    var body: some View {
        Group {
            switch activeTab {
            case .overview:
                RunnerHostOverviewTab(
                    host: host,
                    machine: platformStore.machine,
                    workspace: platformStore.workspace,
                    jobs: platformStore.jobs,
                    hasMoreJobHistory: platformStore.nextCursor != nil
                )
            case .capacity:
                RunnerHostCapacityTab(
                    host: host,
                    machine: platformStore.machine
                )
            case .settings:
                RunnerHostSettingsTab(
                    host: host,
                    settings: runners.fleet.settings
                )
            case .identity:
                RunnerHostIdentityTab(
                    host: host,
                    machine: platformStore.machine,
                    workspace: platformStore.workspace
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Host detail", selection: $activeTab) {
                    ForEach(RunnerHostDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
        }
    }
}
