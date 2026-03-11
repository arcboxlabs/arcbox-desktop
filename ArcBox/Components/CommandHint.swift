import SwiftUI

/// Monospaced command + description for empty state quick-start hints
struct CommandHint: View {
    let command: String
    let description: String

    @State private var copied = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copied ? .green : AppColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered || copied ? 1 : 0)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.background)
            )
            .onHover { hovering in
                isHovered = hovering
            }
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
