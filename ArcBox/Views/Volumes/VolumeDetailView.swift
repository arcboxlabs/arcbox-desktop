import SwiftUI

/// Column 3: volume detail with tab-based toolbar
struct VolumeDetailView: View {
    @Environment(VolumesViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let volume = vm.selectedVolume

        VStack(spacing: 0) {
            if let volume {
                switch vm.activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "Name", value: volume.name)
                            InfoRow(label: "Driver", value: volume.driver)
                            InfoRow(label: "Size", value: volume.sizeDisplay)
                            InfoRow(label: "Created", value: volume.createdAgo)
                        }
                        .infoSectionStyle()
                        .padding(16)
                    }
                case .files:
                    VolumeFilesTab(volume: volume)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.textMuted)
                    Text("No Selection")
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.system(size: 15))
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $vm.activeTab) {
                    ForEach(VolumeDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
    }
}
