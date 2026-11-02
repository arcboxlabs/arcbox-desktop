import AppKit
import SwiftUI
import os

/// Strong ref to the visible notices window; `isReleasedWhenClosed` is off.
private var currentNoticesWindow: NSWindow?

/// Show the Third-Party Notices window, re-focusing it if it is already open.
@MainActor
func showThirdPartyNoticesWindow() {
    if let existing = currentNoticesWindow {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let content: AnyView
    do {
        guard let directory = ThirdPartyNotices.bundled else {
            throw CocoaError(.fileNoSuchFile)
        }
        content = AnyView(ThirdPartyNoticesView(notices: try ThirdPartyNotices.load(from: directory)))
    } catch {
        Log.about.error("Third-party notices failed to load: \(error.localizedDescription, privacy: .private)")
        content = AnyView(
            ContentUnavailableView(
                "Notices Unavailable",
                systemImage: "doc.questionmark",
                description: Text("The third-party notices are missing from this copy of ArcBox.")
            )
        )
    }

    let window = ThirdPartyNoticesWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.title = "Third-Party Notices"
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 680, height: 420)
    let host = NSHostingController(rootView: content)
    host.sceneBridgingOptions = .all
    window.contentViewController = host
    // The assignment resizes the window to the hosting view's fitting size.
    window.setContentSize(NSSize(width: 900, height: 600))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    currentNoticesWindow = window
}

private final class ThirdPartyNoticesWindow: NSWindow {
    override func close() {
        super.close()
        if currentNoticesWindow === self {
            currentNoticesWindow = nil
        }
    }
}
