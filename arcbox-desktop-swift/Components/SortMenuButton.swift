import SwiftUI

/// Sort menu button with dropdown indicator (↕ ▾), matching FilterDropdownButton style
struct SortMenuButton: View {
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("Name") { }
            Button("Date Created") { }
            Button("Size") { }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundStyle(AppColors.textSecondary)
            .frame(width: 34, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? AppColors.hover : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
    }
}
