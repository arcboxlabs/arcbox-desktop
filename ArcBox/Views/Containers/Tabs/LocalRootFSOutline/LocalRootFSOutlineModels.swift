import AppKit

enum FinderListMetrics {
    static let regularRowHeight: CGFloat = 20
    static let groupRowHeight: CGFloat = 18
}

final class LocalFileNode: NSObject {
    let entry: LocalFileEntry
    weak var parent: LocalFileNode?
    var children: [LocalFileNode]?
    var isLoading = false

    init(entry: LocalFileEntry, parent: LocalFileNode?) {
        self.entry = entry
        self.parent = parent
    }

    /// The resource path represented by this node, without its host export prefix.
    func displayPath(rootPath: String) -> String {
        var components: [String] = []
        var node: LocalFileNode? = self
        while let current = node {
            components.append(current.entry.name)
            node = current.parent
        }
        return (rootPath as NSString).appendingPathComponent(
            components.reversed().joined(separator: "/"))
    }
}

final class ContextOutlineView: NSOutlineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0 {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}
