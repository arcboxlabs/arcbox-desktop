import SwiftUI

/// Image detail panel with tabs
struct ImageDetailView: View {
    let image: ImageViewModel?
    @Binding var activeTab: ImageDetailTab

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack {
                Spacer()
                Picker("Tab", selection: $activeTab) {
                    ForEach(ImageDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 250)
                Spacer()
            }
            .frame(height: 52)
            .overlay(alignment: .bottom) { Divider() }

            if let image {
                switch activeTab {
                case .info:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(spacing: 0) {
                                InfoRow(label: "ID", value: image.id)
                                InfoRow(label: "Tag", value: "\(image.repository):\(image.tag)")
                                InfoRow(label: "Created", value: image.createdAgo)
                                InfoRow(label: "Size", value: image.sizeDisplay)
                                InfoRow(label: "Platform", value: "\(image.os)/\(image.architecture)")
                            }

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
                case .terminal:
                    Spacer()
                    Text("Terminal coming soon...")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
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
