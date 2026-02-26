import SwiftUI

/// Column 3: container detail with tab-based toolbar
struct ContainerDetailView: View {
    @Environment(ContainersViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let container = vm.selectedContainer

        VStack(spacing: 0) {
            if let container {
                switch vm.activeTab {
                case .info:
                    ContainerInfoTab(container: container)
                        .id(
                            "info-\(container.id)-\(container.domain ?? "")-\(container.ipAddress ?? "")-\(container.mounts.count)"
                        )
                case .logs:
                    ContainerLogsTab(container: container)
                case .terminal:
                    ContainerTerminalTab(container: container)
                case .files:
                    ContainerFilesTab(container: container)
                }
            } else {
                Spacer()
                Text("No Selection")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 15))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $vm.activeTab) {
                    ForEach(ContainerDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
        }
    }
}
