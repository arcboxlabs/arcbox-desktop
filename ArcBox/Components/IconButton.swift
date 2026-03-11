import SwiftUI

/// Small icon-only button (26x26)
struct IconButton: View {
    let symbol: String
    let action: () -> Void
    var color: Color = AppColors.textSecondary

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? AppColors.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
