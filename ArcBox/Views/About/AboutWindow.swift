import AppKit

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

    let contentSize = NSSize(width: 500, height: 660)
    let panel = AboutPanel(
        contentRect: NSRect(origin: .zero, size: contentSize),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    panel.title = "About ArcBox"
    panel.isReleasedWhenClosed = false

    panel.contentViewController = AboutViewController()
    // Assigning the controller resizes the panel to its view's fitting
    // size, and a scroll view has none: the panel collapsed to a bare
    // title bar (measured 0x32 on macOS 26). Restore the intended size
    // after the assignment, then center the panel at that size.
    panel.setContentSize(contentSize)
    panel.center()
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
