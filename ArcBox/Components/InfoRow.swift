import SwiftUI

/// Label-value pair row for detail panels
struct InfoRow: View {
    let label: String
    let value: String
    var link: URL? = nil
    var rowIndex: Int = 0

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            if let link {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Text(value)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.accent)
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(rowIndex % 2 == 0 ? AppColors.surfaceElevated : Color.clear)
    }
}

// MARK: - Info Section Style

extension View {
    /// Wraps content in a rounded-border card for InfoRow groups
    func infoSectionStyle() -> some View {
        self
            .background(AppColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.border, lineWidth: 0.5)
            )
    }
}
