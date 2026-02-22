import SwiftUI

/// Volumes list + detail panel
struct VolumesListView: View {
    @State private var vm = VolumesViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left: list panel
            VStack(spacing: 0) {
                // "In Use" section header
                HStack {
                    Text("In Use")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // Volume list or empty state
                if vm.volumes.isEmpty {
                    VolumeEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.volumes) { volume in
                                VolumeRowView(
                                    volume: volume,
                                    isSelected: vm.selectedID == volume.id,
                                    onSelect: { vm.selectVolume(volume.id) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: vm.listWidth)

            ListResizeHandle(width: $vm.listWidth, min: 200, max: 500)

            // Right: detail panel
            VolumeDetailView(
                volume: vm.selectedVolume,
                activeTab: $vm.activeTab
            )
        }
        .navigationTitle("Volumes")
        .navigationSubtitle(vm.totalSize)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton()
                IconButton(symbol: "magnifyingglass") {}
                IconButton(symbol: "plus") {}
            }
        }
        .onAppear { vm.loadSampleData() }
    }
}
