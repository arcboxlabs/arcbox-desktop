import AppKit
import DockerClient
import XCTest

@testable import ArcBox

final class NetworksListViewControllerTests: XCTestCase {
    @MainActor
    func testDescendingSortUsesIDToBreakEqualValues() {
        let viewModel = NetworksViewModel()
        viewModel.sortAscending = false

        for ids in [["a", "b"], ["b", "a"]] {
            viewModel.networks = ids.map {
                network(id: $0, name: "same", containerCount: 0)
            }
            XCTAssertEqual(viewModel.sortedNetworks.map(\.id), ["b", "a"])
        }
    }

    @MainActor
    func testRemoveNetworkRejectsNamesAndUnknownIDsBeforeCallingDocker() async throws {
        let viewModel = NetworksViewModel()
        viewModel.networks = [
            network(id: "system-id", name: "host", containerCount: 0)
        ]
        let missingSocket = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let docker = DockerClient(socketPath: missingSocket)

        await viewModel.removeNetwork("host", docker: docker)
        try await docker.shutdown()

        XCTAssertNil(viewModel.lastError)
    }

    func testNetworkInspectNotFoundIsSkippedButServerErrorsSurface() throws {
        let missing = Operations.NetworkInspect.Output.notFound(
            .init(body: .json(.init(message: "network disappeared")))
        )
        XCTAssertNil(try missing.networkForList)

        let serverError = Operations.NetworkInspect.Output.internalServerError(
            .init(body: .json(.init(message: "network driver failed")))
        )
        XCTAssertThrowsError(try serverError.networkForList)
    }

    @MainActor
    func testStateSearchSelectionAndSystemNetworkDeletionRules() async throws {
        let viewModel = NetworksViewModel()
        var didRetry = false
        var controller: NetworksListViewController? = NetworksListViewController(
            viewModel: viewModel,
            loadingTitle: "Loading networks…",
            onRetry: { didRetry = true },
            onDelete: { _ in }
        )
        weak var weakController = controller

        let rootView = try XCTUnwrap(controller?.view)
        let tableView = try XCTUnwrap(findTableView(in: rootView))
        XCTAssertTrue(try XCTUnwrap(tableView.enclosingScrollView).isHidden)

        viewModel.loadState = .failed("Docker unavailable")
        try await waitUntil {
            hostedStateViewAction(titled: "Retry", in: rootView) != nil
        }
        try XCTUnwrap(hostedStateViewAction(titled: "Retry", in: rootView))()
        XCTAssertTrue(didRetry)

        viewModel.loadState = .loaded
        try await waitUntil { self.hasText("No networks yet", in: rootView) }

        viewModel.networks = [
            network(id: "system", name: "host", containerCount: 0),
            network(id: "custom", name: "frontend", containerCount: 2),
            network(id: "unused", name: "backend", containerCount: 0),
        ]
        try await waitUntil { tableView.numberOfRows == 5 }
        XCTAssertFalse(try XCTUnwrap(tableView.enclosingScrollView).isHidden)
        XCTAssertEqual(sectionTitle(at: 0, in: tableView), "In Use")
        XCTAssertEqual(sectionTitle(at: 2, in: tableView), "Unused")

        let (systemRow, systemCell) = try rowAndCell(named: "host", in: tableView)
        let systemDeleteButton = try XCTUnwrap(deleteButton(in: systemCell))
        XCTAssertTrue(systemDeleteButton is ResourceActionButton)
        systemCell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        systemCell.layoutSubtreeIfNeeded()
        let systemContent = try XCTUnwrap(systemDeleteButton.superview as? NSStackView)
        let systemLabels = systemContent.arrangedSubviews[1]
        XCTAssertTrue(systemDeleteButton.isHidden)
        XCTAssertFalse(systemDeleteButton.isEnabled)
        XCTAssertEqual(systemLabels.frame.maxX, systemContent.bounds.maxX, accuracy: 0.5)

        let (customRow, customCell) = try rowAndCell(named: "frontend", in: tableView)
        let customDeleteButton = try XCTUnwrap(deleteButton(in: customCell))
        XCTAssertTrue(customDeleteButton is ResourceActionButton)
        customCell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        customCell.layoutSubtreeIfNeeded()
        let customContent = try XCTUnwrap(customDeleteButton.superview as? NSStackView)
        let customLabels = customContent.arrangedSubviews[1]
        XCTAssertTrue(customDeleteButton.isHidden)
        XCTAssertFalse(customDeleteButton.isEnabled)
        XCTAssertEqual(customContent.spacing, 12)
        XCTAssertEqual(customContent.frame.minX, 24, accuracy: 0.5)
        XCTAssertEqual(customCell.bounds.maxX - customContent.frame.maxX, 24, accuracy: 0.5)
        XCTAssertEqual(customLabels.frame.maxX, customContent.bounds.maxX, accuracy: 0.5)
        tableView.selectRowIndexes(IndexSet(integer: customRow), byExtendingSelection: false)
        customCell.layoutSubtreeIfNeeded()
        XCTAssertTrue(customDeleteButton.isHidden)

        let (unusedRow, unusedCell) = try rowAndCell(named: "backend", in: tableView)
        let unusedDeleteButton = try XCTUnwrap(deleteButton(in: unusedCell))
        unusedCell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        tableView.selectRowIndexes(IndexSet(integer: unusedRow), byExtendingSelection: false)
        unusedCell.layoutSubtreeIfNeeded()
        XCTAssertTrue(unusedDeleteButton.isEnabled)
        XCTAssertFalse(unusedDeleteButton.isHidden)
        XCTAssertEqual(customCell.imageView?.contentTintColor, .secondaryLabelColor)
        tableView.deselectAll(nil)
        customCell.layoutSubtreeIfNeeded()
        XCTAssertEqual(customLabels.frame.maxX, customContent.bounds.maxX, accuracy: 0.5)

        viewModel.searchText = "missing"
        try await waitUntil {
            tableView.numberOfRows == 0 && self.hasText("No Results", in: rootView)
        }

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 5 }
        tableView.selectRowIndexes(IndexSet(integer: systemRow), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "system")
        XCTAssertTrue(systemDeleteButton.isHidden)
        XCTAssertEqual(systemCell.imageView?.contentTintColor, .secondaryLabelColor)

        viewModel.selectedID = "custom"
        try await waitUntil {
            tableView.selectedRow == self.row(named: "frontend", in: tableView)
        }

        viewModel.searchText = "host"
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "custom")

        viewModel.searchText = ""
        try await waitUntil {
            tableView.numberOfRows == 5
                && tableView.selectedRow == self.row(named: "frontend", in: tableView)
        }

        viewModel.networks.removeAll { $0.id == "custom" }
        try await waitUntil { viewModel.selectedID == nil && tableView.selectedRow == -1 }

        controller = nil
        XCTAssertNil(weakController)

        viewModel.searchText = "host"
        await Task.yield()
    }

    @MainActor
    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(
            condition(),
            "Timed out waiting for AppKit observation update",
            file: file,
            line: line
        )
    }

    @MainActor
    private func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }
        return view.subviews.lazy.compactMap { self.findTableView(in: $0) }.first
    }

    @MainActor
    private func hasText(_ text: String, in view: NSView) -> Bool {
        if hostedStateViewDisplays(text, in: view) {
            return true
        }
        if let textField = view as? NSTextField, textField.stringValue == text {
            return true
        }
        return view.subviews.contains { self.hasText(text, in: $0) }
    }

    @MainActor
    private func row(named name: String, in tableView: NSTableView) -> Int? {
        (0..<tableView.numberOfRows).first { row in
            let cell =
                tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
                as? NSTableCellView
            return cell?.textField?.stringValue == name
        }
    }

    @MainActor
    private func sectionTitle(at row: Int, in tableView: NSTableView) -> String? {
        (tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
            .textField?.stringValue
    }

    @MainActor
    private func rowAndCell(
        named name: String,
        in tableView: NSTableView
    ) throws -> (Int, NSTableCellView) {
        let row = try XCTUnwrap(row(named: name, in: tableView))
        let cell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)
        return (row, cell)
    }

    @MainActor
    private func deleteButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
            button.identifier == NSUserInterfaceItemIdentifier("NetworkDeleteButton")
        {
            return button
        }
        return view.subviews.lazy.compactMap { self.deleteButton(in: $0) }.first
    }

    private func network(
        id: String,
        name: String,
        containerCount: Int
    ) -> NetworkViewModel {
        NetworkViewModel(
            id: id,
            name: name,
            driver: "bridge",
            scope: "local",
            createdAt: .distantPast,
            internal: false,
            attachable: false,
            containerCount: containerCount
        )
    }
}
