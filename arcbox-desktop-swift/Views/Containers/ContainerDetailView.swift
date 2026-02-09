import SwiftUI

/// Right panel: tab-based detail view
struct ContainerDetailView: View {
    let container: ContainerViewModel?
    @Binding var activeTab: ContainerDetailTab

    var body: some View {
        VStack(spacing: 0) {
            // Segmented tab bar (52pt height, centered)
            HStack {
                Spacer()
                Picker("Tab", selection: $activeTab) {
                    ForEach(ContainerDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
                Spacer()
            }
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                Divider()
            }

            // Tab content
            if let container {
                switch activeTab {
                case .info:
                    ContainerInfoTab(container: container)
                case .logs:
                    ContainerLogsTab()
                case .terminal:
                    ContainerTerminalTab()
                case .files:
                    ContainerFilesTab()
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
    }
}
