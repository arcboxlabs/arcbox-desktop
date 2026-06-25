import AppKit
import SwiftUI

extension AboutView {
    func linkButton(icon: String, title: String, url: String) -> some View {
        Button {
            guard let destination = URL(string: url) else { return }
            NSWorkspace.shared.open(destination)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
