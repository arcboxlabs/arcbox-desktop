import SwiftUI

/// Single image row
struct ImageRowView: View {
    let image: ImageViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    /// Generate a consistent color based on repository name
    private var imageColor: Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .cyan,
            .blue, .purple, .pink, .indigo, .teal,
        ]
        let hash = image.repository.utf8.reduce(0) { acc, byte in
            acc &* 31 &+ Int(byte)
        }
        return colors[abs(hash) % colors.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            // Image icon
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.18) : AppColors.surfaceElevated)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            isSelected ? AppColors.onAccent : imageColor
                        )
                }

            // Name, size, and age
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(image.repository):\(image.tag)")
                        .font(.system(size: 13))
                        .lineLimit(1)

                    if image.architecture == "amd64" {
                        Text("amd64")
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        isSelected
                                            ? Color.white.opacity(0.18)
                                            : AppColors.surfaceElevated
                                    )
                            )
                    }
                }

                Text("\(image.sizeDisplay), \(image.createdAgo)")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        isSelected ? Color.white.opacity(0.67) : AppColors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button
            if isHovered || isSelected {
                IconButton(
                    symbol: "trash",
                    action: {},
                    color: isSelected ? AppColors.onAccent : AppColors.textSecondary
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(
            isSelected
                ? AppColors.selection
                : (isHovered ? AppColors.hover : Color.clear)
        )
        .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.text)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in isHovered = hovering }
    }
}
