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
