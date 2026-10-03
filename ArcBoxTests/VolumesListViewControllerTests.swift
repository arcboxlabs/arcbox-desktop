import AppKit
import XCTest

@testable import ArcBox

final class VolumesListViewControllerTests: XCTestCase {
    @MainActor
    func testRepeatedModelChangesUpdateRowsAndSelectionWithoutRetainingController() async throws {
        let viewModel = VolumesViewModel()
        viewModel.loadState = .loaded

        var controller: VolumesListViewController? = VolumesListViewController(
            viewModel: viewModel,
            loadingTitle: "Loading volumes…",
            onRetry: {},
            onDelete: { _ in }
        )
        weak var weakController = controller

        let tableView = try XCTUnwrap(findTableView(in: controller?.view))
        XCTAssertTrue(try XCTUnwrap(tableView.enclosingScrollView).isHidden)
        XCTAssertEqual(tableView.numberOfRows, 0)

        viewModel.volumes = [
            volume(name: "data", inUse: true),
            volume(name: "cache", inUse: false),
        ]
        try await waitUntil { tableView.numberOfRows == 4 }

        XCTAssertFalse(try XCTUnwrap(tableView.enclosingScrollView).isHidden)
        XCTAssertEqual(tableView.numberOfRows, 4)
        XCTAssertEqual(tableView.rect(ofRow: 1).height, AppMetrics.rowHeight)
        XCTAssertEqual(tableView.selectionHighlightStyle, .none)
        XCTAssertTrue(
            tableView.rowView(atRow: 1, makeIfNecessary: true) is ResourceListRowView
        )

        let dataCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: 1, makeIfNecessary: true)
                as? NSTableCellView
        )
        let deleteButton = try XCTUnwrap(deleteButton(in: dataCell))
        XCTAssertTrue(deleteButton is ResourceActionButton)
        XCTAssertTrue(dataCell.isAccessibilityElement())
        XCTAssertEqual(dataCell.accessibilityRole(), .group)
        XCTAssertEqual(dataCell.accessibilityLabel(), "data, 1.0 KB, In Use")
        XCTAssertEqual(deleteButton.accessibilityLabel(), "Delete data")
        let sectionCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView
        )
        XCTAssertTrue(sectionCell.isAccessibilityElement())
        XCTAssertEqual(sectionCell.accessibilityLabel(), "In Use")
        dataCell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        dataCell.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(deleteButton.superview as? NSStackView)
        let labels = content.arrangedSubviews[1]
        XCTAssertTrue(deleteButton.isHidden)
        XCTAssertEqual(content.spacing, 12)
        XCTAssertEqual(content.frame.minX, 24, accuracy: 0.5)
        XCTAssertEqual(dataCell.bounds.maxX - content.frame.maxX, 24, accuracy: 0.5)
        XCTAssertEqual(labels.frame.maxX, content.bounds.maxX, accuracy: 0.5)
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        dataCell.layoutSubtreeIfNeeded()
        XCTAssertFalse(deleteButton.isHidden)
        XCTAssertEqual(deleteButton.frame.minX - labels.frame.maxX, 12, accuracy: 0.5)
        XCTAssertEqual(dataCell.imageView?.contentTintColor, .secondaryLabelColor)
        tableView.deselectAll(nil)
        dataCell.layoutSubtreeIfNeeded()
        XCTAssertEqual(labels.frame.maxX, content.bounds.maxX, accuracy: 0.5)

        viewModel.searchText = "cache"
        try await waitUntil { tableView.numberOfRows == 2 }
        XCTAssertEqual(tableView.numberOfRows, 2)

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 4 }
        viewModel.selectedID = "cache"
        try await waitUntil { tableView.selectedRow == 3 }
        XCTAssertEqual(tableView.selectedRow, 3)

        viewModel.searchText = "data"
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "cache")

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 4 && tableView.selectedRow == 3 }

        tableView.deselectAll(nil)
        XCTAssertNil(viewModel.selectedID)

        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "data")

        viewModel.volumes = [volume(name: "cache", inUse: false)]
        try await waitUntil { viewModel.selectedID == nil && tableView.selectedRow == -1 }

        controller = nil
        XCTAssertNil(weakController)

        viewModel.searchText = "cache"
        await Task.yield()
    }

    @MainActor
    func testDescendingSortUsesIDAsTieBreaker() {
        let viewModel = VolumesViewModel()
        viewModel.volumes = [
            volume(name: "alpha", inUse: false),
            volume(name: "beta", inUse: false),
        ]
        viewModel.sortBy = .size
        viewModel.sortAscending = false

        XCTAssertEqual(viewModel.sortedVolumes.map(\.id), ["beta", "alpha"])
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out waiting for AppKit observation update")
    }

    @MainActor
    private func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tableView = view as? NSTableView {
            return tableView
        }
        return view.subviews.lazy.compactMap(findTableView).first
    }

    @MainActor
    private func deleteButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
            button.identifier == NSUserInterfaceItemIdentifier("VolumeDeleteButton")
        {
            return button
        }
        return view.subviews.lazy.compactMap { self.deleteButton(in: $0) }.first
    }

    private func volume(name: String, inUse: Bool) -> VolumeViewModel {
        VolumeViewModel(
            name: name,
            driver: "local",
            mountPoint: "/volumes/\(name)",
            sizeBytes: 1_000,
            createdAt: .distantPast,
            inUse: inUse,
            containerNames: inUse ? ["container"] : []
        )
    }
}
