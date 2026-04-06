import SwiftUI

/// Label-value pair row for detail panels
struct InfoRow: View {
    let label: String
    let value: String
    var link: URL?

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
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
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
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
