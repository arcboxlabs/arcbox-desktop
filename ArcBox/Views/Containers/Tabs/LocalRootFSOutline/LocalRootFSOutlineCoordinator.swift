import AppKit

final class LocalRootFSOutlineCoordinator: NSObject {
    var parent: LocalRootFSOutlineView
    typealias FileSystemService = LocalRootFSService
    var rootNodes: [LocalFileNode] = []
    weak var scrollView: NSScrollView?
    var outlineView: ContextOutlineView?
    weak var nameColumn: NSTableColumn?
    weak var dateColumn: NSTableColumn?
    weak var sizeColumn: NSTableColumn?
    weak var kindColumn: NSTableColumn?
    var reloadKey: String = ""
    var generation: Int = 0
    var hasUserCustomizedColumns = false
    var isApplyingAutoColumnWidths = false

    init(parent: LocalRootFSOutlineView) {
        self.parent = parent
    }

    deinit {
        let scrollView = self.scrollView
        let outlineView = self.outlineView
        if let contentView = scrollView?.contentView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.frameDidChangeNotification,
                object: contentView
            )
        }
        if let outlineView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSTableView.columnDidResizeNotification,
                object: outlineView
            )
        }
    }

    func update(parent: LocalRootFSOutlineView) {
        self.parent = parent
    }

    func makeView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let outline = ContextOutlineView(frame: .zero)
        outline.dataSource = self
        outline.delegate = self
        outline.headerView = NSTableHeaderView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.selectionHighlightStyle = .regular
        outline.backgroundColor = .controlBackgroundColor
        outline.rowSizeStyle = .small
        outline.rowHeight = FinderListMetrics.regularRowHeight
        outline.indentationPerLevel = 14
        outline.indentationMarkerFollowsCell = true
        outline.allowsMultipleSelection = false
        outline.allowsColumnReordering = false
        outline.allowsColumnResizing = true
        outline.columnAutoresizingStyle = .noColumnAutoresizing
        outline.autoresizesOutlineColumn = false
        outline.floatsGroupRows = false
        outline.focusRingType = .none
        outline.autoresizingMask = [.width, .height]

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.minWidth = 80
        nameColumn.width = 320
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outline.addTableColumn(nameColumn)
        outline.outlineTableColumn = nameColumn

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date Modified"
        dateColumn.minWidth = 70
        dateColumn.width = 190
        dateColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outline.addTableColumn(dateColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.minWidth = 60
        sizeColumn.width = 110
        sizeColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outline.addTableColumn(sizeColumn)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.minWidth = 70
        kindColumn.width = 150
        kindColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        outline.addTableColumn(kindColumn)

        outline.doubleAction = #selector(handleDoubleClick)
        outline.target = self
        outline.menu = makeContextMenu()

        scrollView.documentView = outline
        self.scrollView = scrollView
        outlineView = outline
        self.nameColumn = nameColumn
        self.dateColumn = dateColumn
        self.sizeColumn = sizeColumn
        self.kindColumn = kindColumn

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipViewFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTableColumnDidResize(_:)),
            name: NSTableView.columnDidResizeNotification,
            object: outline
        )

        adjustColumnWidths(force: true)
        reloadIfNeeded(force: true)
        return scrollView
    }

    func syncColumnWidthsToVisibleArea() {
        adjustColumnWidths()
    }

    func reloadIfNeeded(force: Bool = false) {
        let newKey = "\(parent.rootURL.path)|\(parent.showHiddenFiles)|\(parent.reloadID)"
        guard force || newKey != reloadKey else { return }
        reloadKey = newKey
        hasUserCustomizedColumns = false
        adjustColumnWidths(force: true)
        loadRootNodes()
    }
}
