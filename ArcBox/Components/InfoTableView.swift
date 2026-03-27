import SwiftUI

/// Reusable table component for info sections (ports, mounts, labels, etc.)
struct InfoTableView<Item: Identifiable, RowContent: View>: View {
    let title: String
    let columns: [String]
    let items: [Item]
    @ViewBuilder let rowContent: (Item) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 0) {
                HStack {
                    ForEach(columns, id: \.self) { column in
                        Text(column)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(AppColors.surfaceElevated)

                ForEach(items) { item in
                    rowContent(item)
                        .font(.system(size: 13))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .overlay(alignment: .bottom) {
                            Divider().opacity(0.3)
                        }
                }
            }
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.border, lineWidth: 0.5)
            )
        }
    }
}
