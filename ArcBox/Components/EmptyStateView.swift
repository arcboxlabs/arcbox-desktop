import SwiftUI

/// Reusable empty state component with icon, title, and an optional custom content area.
struct EmptyStateView<Content: View>: View {
    let icon: String
    let title: String
    let content: Content

    init(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.surfaceElevated)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(AppColors.textMuted)
            }

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

            content
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.surfaceElevated)
                )

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

/// Convenience initializer for empty states without extra content.
extension EmptyStateView where Content == EmptyView {
    init(icon: String, title: String) {
        self.icon = icon
        self.title = title
        self.content = EmptyView()
    }
}
