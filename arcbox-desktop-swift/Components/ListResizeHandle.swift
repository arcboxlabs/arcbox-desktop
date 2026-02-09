import SwiftUI

/// Drag-to-resize handle between list and detail panels
struct ListResizeHandle: View {
    @Binding var width: CGFloat
    let min: CGFloat
    let max: CGFloat

    @State private var isHovered: Bool = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? AppColors.border : AppColors.borderSubtle)
            .frame(width: 1)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = width + value.translation.width
                        width = Swift.min(Swift.max(newWidth, min), max)
                    }
            )
    }
}
