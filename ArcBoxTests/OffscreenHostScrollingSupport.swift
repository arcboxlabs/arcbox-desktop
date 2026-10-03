import AppKit
import SwiftUI
import XCTest

extension OffscreenHost {
    /// Hosts `root` in a window whose content area measures `contentSize`.
    ///
    /// Assigning an `NSHostingController` to a window sizes the window to the
    /// root's ideal size — a bare logs tab fits in 325×125 points — so the
    /// designated initializer's `size` is gone before the first layout. Setting
    /// the content size afterwards makes the host as large as a real detail pane,
    /// which is what a scrolling test needs: a viewport of a few rows hides a
    /// cost that scales with the visible rows.
    convenience init<Root: View>(_ root: Root, contentSize: NSSize) {
        self.init(root, size: contentSize)
        window.setContentSize(contentSize)
        settle()
    }

    /// Every `NSScrollView` SwiftUI created, outermost first.
    func scrollViews() -> [NSScrollView] {
        allViews().compactMap { $0 as? NSScrollView }
    }
}

extension NSScrollView {
    /// The document's height, or 0 without a document view.
    var documentHeight: CGFloat {
        documentView?.frame.height ?? 0
    }

    /// Whether the visible rect ends at the document's end, to the pixel.
    var isScrolledToBottom: Bool {
        abs(documentVisibleRect.maxY - documentHeight) < 1
    }

    /// Scrolls the document so its visible rect starts `y` points from the top,
    /// as a user's scroll gesture would.
    func scroll(toY y: CGFloat) {
        contentView.scroll(to: NSPoint(x: documentVisibleRect.origin.x, y: y))
        reflectScrolledClipView(contentView)
    }
}
