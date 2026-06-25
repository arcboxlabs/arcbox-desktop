import AppKit

extension LocalRootFSOutlineCoordinator: NSOutlineViewDataSource, NSOutlineViewDelegate {
    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? LocalFileNode {
            return node.children?.count ?? 0
        }
        return rootNodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? LocalFileNode {
            return node.children?[index] as Any
        }
        return rootNodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? LocalFileNode else { return false }
        return node.entry.isExpandable
    }

    // MARK: NSOutlineViewDelegate

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? LocalFileNode else { return }
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
        guard let node = item as? LocalFileNode,
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

    func nameCell(for node: LocalFileNode, outlineView: NSOutlineView) -> NSView {
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

    func textCell(
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
