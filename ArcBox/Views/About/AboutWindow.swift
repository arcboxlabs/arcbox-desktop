import AppKit
import SwiftUI

/// Tracks the visible About panel to prevent duplicates.
/// Strong ref: lifecycle is managed manually since isReleasedWhenClosed is off.
private var currentAboutPanel: NSPanel?

/// Show the custom About ArcBox window.
/// Re-focuses the existing panel if already visible.
@MainActor
func showAboutWindow() {
    if let existing = currentAboutPanel {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let panel = AboutPanel(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 660),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    panel.title = "About ArcBox"
    panel.isReleasedWhenClosed = false
    panel.center()

    let hostingView = NSHostingView(rootView: AboutView())
    panel.contentView = hostingView
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    currentAboutPanel = panel
}

// MARK: - Panel subclass for Esc key dismissal

private final class AboutPanel: NSPanel {
    override func close() {
        super.close()
        if currentAboutPanel === self {
            currentAboutPanel = nil
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
