import SwiftUI

/// Column 3: image detail with tab-based toolbar
struct ImageDetailView: View {
    @Environment(ImagesViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let image = vm.selectedImage

        VStack(spacing: 0) {
            if let image {
                ZStack {
                    // Info / Files tabs: created and destroyed normally
                    switch vm.activeTab {
                    case .info:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(spacing: 0) {
                                    InfoRow(label: "ID", value: image.dockerId)
                                    InfoRow(label: "Tag", value: "\(image.repository):\(image.tag)")
                                    InfoRow(label: "Created", value: image.createdAgo)
                                    InfoRow(label: "Size", value: image.sizeDisplay)
                                    if let platform = image.platformDisplay {
                                        InfoRow(label: "Platform", value: platform)
                                    }
                                }
                                .infoSectionStyle()
                            }
                            .padding(16)
                        }
                    case .files:
                        ImageFilesTab(image: image)
                    case .terminal:
                        EmptyView()
                    }

                    // Terminal tab: always in the view hierarchy to avoid
                    // NSView destruction/recreation that causes hangs.
                    // Hidden via opacity when not active.
                    ImageTerminalTab(image: image, isActive: vm.activeTab == .terminal)
                        .opacity(vm.activeTab == .terminal ? 1 : 0)
                        .allowsHitTesting(vm.activeTab == .terminal)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "circle.circle")
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
            DetailTabPicker(selection: $vm.activeTab)
        }
    }
}
