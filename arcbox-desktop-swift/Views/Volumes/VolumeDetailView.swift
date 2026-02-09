import SwiftUI

/// Volume detail panel with tabs
struct VolumeDetailView: View {
    let volume: VolumeViewModel?
    @Binding var activeTab: VolumeDetailTab

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack {
                Spacer()
                Picker("Tab", selection: $activeTab) {
                    ForEach(VolumeDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
                Spacer()
            }
            .frame(height: 52)
            .overlay(alignment: .bottom) { Divider() }

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
                    Spacer()
                    Text("Files coming soon...")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
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
