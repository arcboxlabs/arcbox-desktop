import SwiftUI

/// Column 2: images list with toolbar
struct ImagesListView: View {
    @Environment(ImagesViewModel.self) private var vm

    var body: some View {
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

            if vm.images.isEmpty {
                ImageEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.sortedImages) { image in
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
        .navigationTitle("Images")
        .navigationSubtitle(vm.totalSize)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
                Button(action: { vm.showPullImageSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: Bindable(vm).showPullImageSheet) {
            PullImageSheet()
        }
        .onAppear { vm.loadSampleData() }
    }
}
