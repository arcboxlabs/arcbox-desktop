import SwiftUI
import SwiftTerm

/// NSViewRepresentable wrapper to embed SwiftTerm's TerminalView in SwiftUI.
///
/// The `delegate` is retained by the Coordinator to prevent deallocation,
/// since SwiftTerm's `terminalDelegate` is a weak reference.
struct SwiftTermView: NSViewRepresentable {
    let delegate: any TerminalViewDelegate
    let onTerminalCreated: (TerminalView) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: .zero)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Store delegate in coordinator so it stays alive
        context.coordinator.delegate = delegate
        tv.terminalDelegate = delegate

        onTerminalCreated(tv)

        // Request keyboard focus after the view is in the window hierarchy
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
        }
        return tv
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Reconfigure colors when system appearance changes
        TerminalAppearance.configure(nsView)
    }

    class Coordinator {
        var delegate: (any TerminalViewDelegate)?
    }
}
