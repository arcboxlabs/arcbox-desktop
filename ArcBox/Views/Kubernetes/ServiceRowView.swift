import AppKit
import SwiftUI

/// Single service row
struct ServiceRowView: View {
    let service: ServiceViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Service icon
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.iconBackground)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "network")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }

            // Name and type
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(service.type.rawValue)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.67) : AppColors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? AppColors.selection
                        : (isHovered ? AppColors.hover : Color.clear)
                )
        )
        .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.text)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(service.name), \(service.type.rawValue)")
        .onTapGesture(perform: onSelect)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button("Copy Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(service.name, forType: .string)
            }
        }
    }
}
