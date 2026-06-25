import AppKit

extension LocalRootFSOutlineCoordinator {
    @objc func handleClipViewBoundsDidChange() {
        adjustColumnWidths()
    }

    @objc func handleClipViewFrameDidChange() {
        adjustColumnWidths()
    }

    @objc func handleTableColumnDidResize(_ notification: Notification) {
        markUserColumnCustomizationIfNeeded(from: notification)
    }

    func adjustColumnWidths(force: Bool = false) {
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

    func markUserColumnCustomizationIfNeeded(from notification: Notification) {
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

}
