import AppKit

extension LocalRootFSOutlineCoordinator {
    func selectedNode() -> LocalFileNode? {
        guard let outlineView else { return nil }
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? LocalFileNode
    }

    func toggleExpandOrCollapse(_ node: LocalFileNode) {
        guard let outlineView, node.entry.isExpandable else { return }
        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            loadChildrenIfNeeded(for: node)
            outlineView.expandItem(node)
        }
    }

    func open(_ node: LocalFileNode) {
        if node.entry.isExpandable {
            toggleExpandOrCollapse(node)
        } else {
            parent.onOpenURL(node.entry.url)
        }
    }

    func makeContextMenu() -> NSMenu {
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

    @objc func handleDoubleClick() {
        guard let node = selectedNode() else { return }
        open(node)
    }

    @objc func openSelectedItem() {
        guard let node = selectedNode() else { return }
        open(node)
    }

    @objc func revealSelectedItem() {
        guard let node = selectedNode() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.entry.url])
    }

    @objc func copySelectedPath() {
        guard let node = selectedNode() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.entry.url.path, forType: .string)
    }

}
