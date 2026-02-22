import SwiftUI

/// Images list + detail panel
struct ImagesListView: View {
    @State private var vm = ImagesViewModel()

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

                // Image list or empty state
                if vm.images.isEmpty {
                    ImageEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.images) { image in
                                ImageRowView(
                                    image: image,
                                    isSelected: vm.selectedID == image.id,
                                    onSelect: { vm.selectImage(image.id) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: vm.listWidth)

            ListResizeHandle(width: $vm.listWidth, min: 200, max: 500)

            // Right: detail panel
            ImageDetailView(
                image: vm.selectedImage,
                activeTab: $vm.activeTab
            )
        }
        .navigationTitle("Images")
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
