import SwiftUI

/// Volume detail panel with tabs
struct VolumeDetailView: View {
    let volume: VolumeViewModel?
    @Binding var activeTab: VolumeDetailTab

    var body: some View {
        VStack(spacing: 0) {
            // Detail toolbar
            HStack {
                Picker("Tab", selection: $activeTab) {
                    ForEach(VolumeDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if let volume {
                switch activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "Name", value: volume.name)
                            InfoRow(label: "Driver", value: volume.driver)
                            InfoRow(label: "Size", value: volume.sizeDisplay)
                            InfoRow(label: "Created", value: volume.createdAgo)
                        }
                        .padding(16)
                    }
                case .files:
                    VolumeFilesTab(volume: volume)
                }
            } else {
                Spacer()
                Text("No Selection")
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}
