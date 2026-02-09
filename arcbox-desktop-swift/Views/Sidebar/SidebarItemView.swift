import SwiftUI

/// Individual sidebar row with icon + label
struct SidebarItemView: View {
    let item: NavItem
    let isSelected: Bool
    var collapsed: Bool = false

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: collapsed ? 0 : 8) {
            Image(systemName: item.sfSymbol)
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                .frame(width: 18, height: 18)

            if !collapsed {
                Text(item.label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(AppColors.text)
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
        .padding(.horizontal, collapsed ? 0 : 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? AppColors.sidebarItemSelected
                        : (isHovered ? AppColors.sidebarItemHover : Color.clear)
                )
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
