import SwiftUI

/// Images list + detail panel
struct ImagesListView: View {
    @State private var vm = ImagesViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Left: list panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Images")
                            .font(.system(size: 13, weight: .semibold))
                        Text(vm.totalSize)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        IconButton(symbol: "arrow.up.arrow.down") {}
                        IconButton(symbol: "magnifyingglass") {}
                        IconButton(symbol: "plus") {}
                    }
                }
                .frame(height: 52)
                .padding(.horizontal, 16)
                .overlay(alignment: .bottom) { Divider() }

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
        .onAppear { vm.loadSampleData() }
    }
}
