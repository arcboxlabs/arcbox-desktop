import SwiftUI

/// Displays a remote icon image with a fallback SF Symbol.
///
/// When `iconURL` is non-nil, loads the image asynchronously and displays it
/// inside a rounded rectangle. Falls back to the given SF Symbol when the URL
/// is nil, during loading, or on failure.
struct RemoteIconView: View {
    let iconURL: String?
    let fallbackSymbol: String
    let size: CGFloat
    let cornerRadius: CGFloat
    let symbolFontSize: CGFloat
    let foregroundColor: Color
    let backgroundColor: Color

    init(
        iconURL: String?,
        fallbackSymbol: String = "shippingbox",
        size: CGFloat = 32,
        cornerRadius: CGFloat = 6,
        symbolFontSize: CGFloat = 16,
        foregroundColor: Color,
        backgroundColor: Color
    ) {
        self.iconURL = iconURL
        self.fallbackSymbol = fallbackSymbol
        self.size = size
        self.cornerRadius = cornerRadius
        self.symbolFontSize = symbolFontSize
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    var body: some View {
        if let iconURL, let url = URL(string: iconURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size - 4, height: size - 4)
                default:
                    fallbackIcon
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
            )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .frame(width: size, height: size)
                .overlay {
                    fallbackIcon
                }
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: fallbackSymbol)
            .font(.system(size: symbolFontSize))
            .foregroundStyle(foregroundColor)
    }
}
