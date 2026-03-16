import AppKit
import SwiftUI

/// Shows a floating "Coming Soon" panel centered on screen.
func showComingSoonPanel() {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 280, height: 260),
        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.center()

    let hostingView = NSHostingView(
        rootView: ComingSoonContent(onDismiss: {
            panel.close()
        }))
    hostingView.wantsLayer = true
    hostingView.layer?.cornerRadius = 20
    hostingView.layer?.masksToBounds = true
    panel.contentView = hostingView
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

private struct ComingSoonContent: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Coming Soon!")
                .font(.title2)
                .fontWeight(.semibold)

            Button(action: onDismiss) {
                Text("OK")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}
