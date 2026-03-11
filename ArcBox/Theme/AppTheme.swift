import SwiftUI

// MARK: - Card Modifier

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, lineWidth: 1)
            )
    }
}

// MARK: - Badge Modifier

struct BadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(AppColors.surfaceElevated)
            .foregroundStyle(AppColors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Section Header Style

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.sectionHeader)
            .textCase(.uppercase)
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    func badgeStyle() -> some View {
        modifier(BadgeModifier())
    }

    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderStyle())
    }
}
