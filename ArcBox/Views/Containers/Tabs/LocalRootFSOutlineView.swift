import AppKit
import SwiftUI

struct LocalRootFSOutlineView: NSViewRepresentable {
    let rootURL: URL
    let showHiddenFiles: Bool
    let reloadID: String
    @Binding var selectedPath: String?
    let onOpenURL: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
        context.coordinator.syncColumnWidthsToVisibleArea()
        context.coordinator.reloadIfNeeded()
    }

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        private enum FinderListMetrics {
            static let regularRowHeight: CGFloat = 20
            static let groupRowHeight: CGFloat = 18
        }

        private final class Node: NSObject {
            let entry: LocalFileEntry
            weak var parent: Node?
            var children: [Node]?
            var isLoading = false

            init(entry: LocalFileEntry, parent: Node?) {
                self.entry = entry
                self.parent = parent
            }
        }

        private final class ContextOutlineView: NSOutlineView {
            override func menu(for event: NSEvent) -> NSMenu? {
                let point = convert(event.locationInWindow, from: nil)
                let row = row(at: point)
                if row >= 0 {
                    selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                return super.menu(for: event)
            }
        }

        private var parent: LocalRootFSOutlineView
        private let fileService = LocalRootFSService()
        private var rootNodes: [Node] = []
        private weak var scrollView: NSScrollView?
        private var outlineView: ContextOutlineView?
        private weak var nameColumn: NSTableColumn?
        private weak var dateColumn: NSTableColumn?
        private weak var sizeColumn: NSTableColumn?
        private weak var kindColumn: NSTableColumn?
        private var reloadKey: String = ""
        private var generation: Int = 0
        private var hasUserCustomizedColumns = false
        private var isApplyingAutoColumnWidths = false

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

        private func loadRootNodes() {
            generation += 1
            let currentGeneration = generation
            let rootURL = parent.rootURL
            let showHidden = parent.showHiddenFiles

            rootNodes = []
            outlineView?.reloadData()
            parent.selectedPath = nil

            DispatchQueue.global(qos: .userInitiated).async { [fileService] in
                let entries: [LocalFileEntry]
                do {
                    entries = try fileService.listDirectory(at: rootURL, showHiddenFiles: showHidden)
                } catch {
                    entries = []
                }

                DispatchQueue.main.async {
                    guard currentGeneration == self.generation else { return }
                    self.rootNodes = entries.map { Node(entry: $0, parent: nil) }
                    self.outlineView?.reloadData()
                    self.adjustColumnWidths(force: true)
                    DispatchQueue.main.async {
                        self.adjustColumnWidths(force: true)
                    }
                }
            }
        }

        private func loadChildrenIfNeeded(for node: Node) {
            guard node.entry.isExpandable, node.children == nil, !node.isLoading else { return }

            node.isLoading = true
            let currentGeneration = generation
            let showHidden = parent.showHiddenFiles

            DispatchQueue.global(qos: .userInitiated).async { [fileService] in
                let children: [LocalFileEntry]
                do {
                    children = try fileService.listDirectory(at: node.entry.url, showHiddenFiles: showHidden)
                } catch {
                    children = []
                }

                DispatchQueue.main.async {
                    guard currentGeneration == self.generation else { return }
                    node.isLoading = false
                    node.children = children.map { Node(entry: $0, parent: node) }
                    self.outlineView?.reloadItem(node, reloadChildren: true)
                    self.adjustColumnWidths()
                    DispatchQueue.main.async {
                        self.adjustColumnWidths()
                    }
                }
            }
        }

        @objc private func handleClipViewBoundsDidChange() {
            adjustColumnWidths()
        }

        @objc private func handleClipViewFrameDidChange() {
            adjustColumnWidths()
        }

        @objc private func handleTableColumnDidResize(_ notification: Notification) {
            markUserColumnCustomizationIfNeeded(from: notification)
        }

        private func adjustColumnWidths(force: Bool = false) {
            if hasUserCustomizedColumns && !force {
                return
            }

            guard let outlineView,
                let scrollView = outlineView.enclosingScrollView,
                let nameColumn,
                let dateColumn,
                let sizeColumn,
                let kindColumn
            else {
                return
            }

            let visibleWidth = scrollView.contentSize.width
            guard visibleWidth > 0 else { return }

            let spacing = CGFloat(max(outlineView.numberOfColumns - 1, 0)) * outlineView.intercellSpacing.width
            let usableWidth = max(visibleWidth - spacing, 220)

            let nameWidth = floor(usableWidth * 0.38)
            let dateWidth = floor(usableWidth * 0.25)
            let sizeWidth = floor(usableWidth * 0.13)
            let kindWidth = max(usableWidth - nameWidth - dateWidth - sizeWidth, 60)

            isApplyingAutoColumnWidths = true
            nameColumn.width = nameWidth
            dateColumn.width = dateWidth
            sizeColumn.width = sizeWidth
            kindColumn.width = kindWidth
            outlineView.frame.size.width = visibleWidth
            isApplyingAutoColumnWidths = false
        }

        func outlineViewColumnDidResize(_ notification: Notification) {
            markUserColumnCustomizationIfNeeded(from: notification)
        }

        private func markUserColumnCustomizationIfNeeded(from notification: Notification) {
            guard !isApplyingAutoColumnWidths else { return }

            let wasUserResize =
                (notification.userInfo?["NSTableColumnUserResized"] as? Bool)
                ?? {
                    guard let eventType = NSApp.currentEvent?.type else { return false }
                    return eventType == .leftMouseDragged || eventType == .leftMouseUp
                }()

            if wasUserResize {
                hasUserCustomizedColumns = true
            }
        }

        private func selectedNode() -> Node? {
            guard let outlineView else { return nil }
            let row = outlineView.selectedRow
            guard row >= 0 else { return nil }
            return outlineView.item(atRow: row) as? Node
        }

        private func toggleExpandOrCollapse(_ node: Node) {
            guard let outlineView, node.entry.isExpandable else { return }
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                loadChildrenIfNeeded(for: node)
                outlineView.expandItem(node)
            }
        }

        private func open(_ node: Node) {
            if node.entry.isExpandable {
                toggleExpandOrCollapse(node)
            } else {
                parent.onOpenURL(node.entry.url)
            }
        }

        private func makeContextMenu() -> NSMenu {
            let menu = NSMenu(title: "File")
            menu.autoenablesItems = false

            let open = NSMenuItem(title: "Open", action: #selector(openSelectedItem), keyEquivalent: "")
            open.target = self
            menu.addItem(open)

            let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealSelectedItem), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)

            menu.addItem(.separator())

            let copyPath = NSMenuItem(title: "Copy Path", action: #selector(copySelectedPath), keyEquivalent: "")
            copyPath.target = self
            menu.addItem(copyPath)

            return menu
        }

        @objc private func handleDoubleClick() {
            guard let node = selectedNode() else { return }
            open(node)
        }

        @objc private func openSelectedItem() {
            guard let node = selectedNode() else { return }
            open(node)
        }

        @objc private func revealSelectedItem() {
            guard let node = selectedNode() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([node.entry.url])
        }

        @objc private func copySelectedPath() {
            guard let node = selectedNode() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.entry.url.path, forType: .string)
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let node = item as? Node {
                return node.children?.count ?? 0
            }
            return rootNodes.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let node = item as? Node {
                return node.children?[index] as Any
            }
            return rootNodes[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            return node.entry.isExpandable
        }

        // MARK: NSOutlineViewDelegate

        func outlineViewItemWillExpand(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? Node else { return }
            loadChildrenIfNeeded(for: node)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let node = selectedNode() else {
                parent.selectedPath = nil
                return
            }
            parent.selectedPath = node.entry.id
        }

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            false
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            self.outlineView(outlineView, isGroupItem: item)
                ? FinderListMetrics.groupRowHeight
                : FinderListMetrics.regularRowHeight
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let node = item as? Node,
                let identifier = tableColumn?.identifier.rawValue
            else {
                return nil
            }

            switch identifier {
            case "name":
                return nameCell(for: node, outlineView: outlineView)
            case "date":
                return textCell(
                    outlineView: outlineView,
                    identifier: "dateCell",
                    text: node.entry.dateDisplay,
                    alignment: .left
                )
            case "size":
                return textCell(
                    outlineView: outlineView,
                    identifier: "sizeCell",
                    text: node.entry.sizeDisplay,
                    alignment: .left
                )
            case "kind":
                return textCell(
                    outlineView: outlineView,
                    identifier: "kindCell",
                    text: node.entry.kind,
                    alignment: .left
                )
            default:
                return nil
            }
        }

        private func nameCell(for node: Node, outlineView: NSOutlineView) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("nameCell")
            let cell =
                outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
                ?? NSTableCellView(frame: .zero)
            cell.identifier = identifier

            if cell.imageView == nil {
                let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                cell.addSubview(imageView)
                cell.imageView = imageView

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingMiddle
                cell.addSubview(textField)
                cell.textField = textField

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),

                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }

            cell.imageView?.image = NSWorkspace.shared.icon(forFile: node.entry.url.path)
            cell.imageView?.contentTintColor = nil
            cell.textField?.stringValue = node.entry.name
            cell.textField?.font = .systemFont(ofSize: 12)
            return cell
        }

        private func textCell(
            outlineView: NSOutlineView,
            identifier: String,
            text: String,
            alignment: NSTextAlignment
        ) -> NSView {
            let viewIdentifier = NSUserInterfaceItemIdentifier(identifier)
            let cellView: NSTableCellView
            if let reusable = outlineView.makeView(withIdentifier: viewIdentifier, owner: nil) as? NSTableCellView {
                cellView = reusable
            } else {
                let created = NSTableCellView(frame: .zero)
                created.identifier = viewIdentifier

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.font = .systemFont(ofSize: 11)
                textField.textColor = NSColor.secondaryLabelColor
                textField.lineBreakMode = .byTruncatingTail
                created.addSubview(textField)
                created.textField = textField

                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: created.centerYAnchor),
                ])

                cellView = created
            }

            guard let textField = cellView.textField else { return cellView }
            textField.stringValue = text
            textField.alignment = alignment
            return cellView
        }
    }
}
