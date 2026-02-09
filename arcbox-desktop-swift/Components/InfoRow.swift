import SwiftUI

/// Label-value pair row for detail panels
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}
