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
                                    InfoRow(label: "Platform", value: "\(image.os)/\(image.architecture)")
                                }
                                .infoSectionStyle()

                                // Export button
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(AppColors.surfaceElevated)
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            Image(systemName: "arrow.down.circle")
                                                .font(.system(size: 14))
                                        }

                                    Text("Export")
                                        .font(.system(size: 13))

                                    Spacer()

                                    Text("\u{203A}")
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
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
                Text("No Selection")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 15))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $vm.activeTab) {
                    ForEach(ImageDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)
            }
        }
    }
}
