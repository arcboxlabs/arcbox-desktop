import SwiftUI

/// Monospaced command + description for empty state quick-start hints
struct CommandHint: View {
    let command: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.background)
                )
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
