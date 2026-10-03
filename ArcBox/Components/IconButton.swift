import SwiftUI

/// Small icon-only button (26x26). `label` is what VoiceOver reads; the
/// symbol alone does not say what the button does or to which resource.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var color: Color = AppColors.textSecondary

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: AppMetrics.rowActionButton, height: AppMetrics.rowActionButton)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? AppColors.hover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
