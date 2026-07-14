import SwiftUI

/// Circular user avatar loaded from a URL, falling back to the Apple-style
/// placeholder (white silhouette on gray, as in Contacts and the Apple
/// Account pane). The placeholder also covers the loading and failure
/// phases of the remote image.
struct AvatarView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .gray)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("User avatar")
    }
}

#Preview {
    HStack(spacing: 16) {
        AvatarView(url: nil, size: 64)
        AvatarView(url: nil, size: 28)
    }
    .padding()
}
