import AppKit
import SwiftUI

/// Tracks the currently visible "Coming Soon" panel so we don't create duplicates.
/// Strong ref: we manage the lifecycle ourselves since isReleasedWhenClosed is off.
private var currentPanel: NSPanel?

/// Shows a floating "Coming Soon" panel centered on screen.
/// Re-focuses the existing panel if one is already visible.
@MainActor
func showComingSoonPanel() {
    if let existing = currentPanel {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let panel = ComingSoonPanel(
        contentRect: NSRect(x: 0, y: 0, width: 280, height: 260),
        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
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
            currentPanel?.close()
            currentPanel = nil
        }))
    hostingView.wantsLayer = true
    hostingView.layer?.cornerRadius = 20
    hostingView.layer?.masksToBounds = true
    panel.contentView = hostingView
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    currentPanel = panel
}

// MARK: - Panel subclass for Esc key support

private final class ComingSoonPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        close()
        currentPanel = nil
    }
}

// MARK: - Content

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
