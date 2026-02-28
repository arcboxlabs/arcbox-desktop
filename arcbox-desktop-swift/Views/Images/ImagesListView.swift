import SwiftUI
import DockerClient

/// Column 2: images list with toolbar
struct ImagesListView: View {
    @Environment(ImagesViewModel.self) private var vm
    @Environment(\.dockerClient) private var docker

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
                                onSelect: { vm.selectImage(image.id) },
                                onDelete: {
                                    Task { await vm.removeImage(image.id, docker: docker) }
                                }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Images")
        .navigationSubtitle(vm.totalSize)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: { vm.showPullImageSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: Bindable(vm).showPullImageSheet) {
            PullImageSheet()
        }
        .task { await vm.loadImages(docker: docker) }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            Task { await vm.loadImages(docker: docker) }
        }
    }
}
