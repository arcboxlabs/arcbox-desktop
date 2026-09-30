import AppKit
import SwiftUI
import XCTest

/// Hosts a SwiftUI root in an offscreen `NSWindow` so the AppKit hierarchy —
/// title bar and toolbar included — can be inspected and laid out on demand.
///
/// The window is never ordered on screen: a laid-out `contentViewController`
/// is enough for SwiftUI to materialize its platform views and its toolbar.
@MainActor
final class OffscreenHost {
    let window: NSWindow

    init<Root: View>(_ root: Root, size: NSSize = NSSize(width: 960, height: 640)) {
        let controller = NSHostingController(rootView: root)
        controller.sceneBridgingOptions = .all
        window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        settle()
    }

    func close() {
        window.close()
    }

    /// One non-blocking run-loop pass followed by a forced layout: enough for
    /// an `@Observable` mutation to reach the view graph and be laid out.
    func pump() {
        RunLoop.main.run(until: Date())
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    /// Lets asynchronous SwiftUI work (`.task`, toolbar bridging) land.
    func settle(passes: Int = 10) {
        for _ in 0..<passes {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
    }

    /// Wall time of `count` hot updates, each followed by a layout pass.
    func measureUpdates(count: Int, mutate: () -> Void) -> Duration {
        settle()
        return ContinuousClock().measure {
            for _ in 0..<count {
                mutate()
                pump()
            }
        }
    }

    // MARK: - AppKit hierarchy

    /// Every view in the window, title bar and toolbar item views included.
    func allViews() -> [NSView] {
        var views: [NSView] = []
        var roots: [NSView] = []
        if let frame = window.contentView?.superview {
            roots.append(frame)
        } else if let content = window.contentView {
            roots.append(content)
        }
        roots.append(contentsOf: (window.toolbar?.items ?? []).compactMap(\.view))
        var seen = Set<ObjectIdentifier>()
        func walk(_ view: NSView) {
            guard seen.insert(ObjectIdentifier(view)).inserted else { return }
            views.append(view)
            view.subviews.forEach(walk)
        }
        roots.forEach(walk)
        return views
    }

    func viewClassNames() -> [String] {
        allViews().map { String(describing: type(of: $0)) }
    }

    /// Class names of every view SwiftUI created for a segmented control: the
    /// `PlatformViewRepresentableAdaptor<SystemSegmentedControl>` host, the
    /// `NSSegmentedControl` subclass, and its inner `_NSCoreHostingView`.
    func segmentedControlClassNames() -> [String] {
        viewClassNames().filter { $0.contains("Segmented") }
    }

    func segmentedControls() -> [NSSegmentedControl] {
        allViews().compactMap { $0 as? NSSegmentedControl }
    }

    // MARK: - Accessibility

    /// One node of the accessibility tree, read through dynamic messaging:
    /// SwiftUI's synthetic elements answer the `NSAccessibility` selectors
    /// without declaring `NSAccessibilityProtocol`.
    struct AccessibilityNode {
        let object: NSObject
        let depth: Int
        let role: String
        let subrole: String
        let label: String
        let value: String
        let isSelected: Bool

        var description: String {
            String(repeating: "  ", count: depth)
                + "\(type(of: object)) role=\(role) subrole=\(subrole) label=\(label) value=\(value) selected=\(isSelected)"
        }

        func press() {
            _ = object.perform(NSSelectorFromString("accessibilityPerformPress"))
        }
    }

    /// The accessibility tree under `root`, depth-first.
    func accessibilityTree(from root: NSObject, depth: Int = 0, limit: Int = 8) -> [AccessibilityNode] {
        guard depth < limit else { return [] }
        func string(_ key: String, getter: String? = nil) -> String {
            guard root.responds(to: NSSelectorFromString(getter ?? key)) else { return "-" }
            guard let value = root.value(forKey: key) else { return "-" }
            return String(describing: value)
        }
        let selected =
            root.responds(to: NSSelectorFromString("isAccessibilitySelected"))
            && (root.value(forKey: "accessibilitySelected") as? Bool ?? false)
        var nodes = [
            AccessibilityNode(
                object: root,
                depth: depth,
                role: string("accessibilityRole"),
                subrole: string("accessibilitySubrole"),
                label: string("accessibilityLabel"),
                value: string("accessibilityValue"),
                isSelected: selected
            )
        ]
        let children =
            root.responds(to: NSSelectorFromString("accessibilityChildren"))
            ? root.value(forKey: "accessibilityChildren") as? [Any] : nil
        for case let child as NSObject in children ?? [] {
            nodes += accessibilityTree(from: child, depth: depth + 1, limit: limit)
        }
        return nodes
    }

    func accessibilityDump(from root: NSObject) -> String {
        accessibilityTree(from: root).map(\.description).joined(separator: "\n")
    }
}
