import AppKit
import XCTest

@testable import ArcBox

final class NetworkDetailViewControllerTests: XCTestCase {
    @MainActor
    func testInspectFailureIsNotEmptyAndRetryCanReachEmptyWithoutRetainingController()
        async throws
    {
        let viewModel = NetworksViewModel()
        var attempts = 0
        let loader: NetworkDetailViewController.LoadContainers = { _ in
            attempts += 1
            switch attempts {
            case 1:
                throw InspectError()
            case 2:
                return []
            default:
                return [
                    .init(
                        id: "container-id",
                        name: "web",
                        ipv4: "172.18.0.2/16",
                        mac: "02:42:ac:12:00:02"
                    )
                ]
            }
        }
        var controller: NetworkDetailViewController? = NetworkDetailViewController(
            viewModel: viewModel,
            loadContainers: loader,
            runningContainerIDs: []
        )
        weak var weakController = controller

        let rootView = try XCTUnwrap(controller?.view)
        let tableView = try XCTUnwrap(findTableView(in: rootView))
        XCTAssertTrue(hasText("No Selection", in: rootView))

        viewModel.networks = [network()]
        viewModel.selectedID = "network-id"

        try await waitUntil {
            self.hasText("Failed to inspect network", in: rootView)
                && hostedStateViewAction(titled: "Retry", in: rootView) != nil
        }
        XCTAssertFalse(hasText("No containers connected", in: rootView))

        try XCTUnwrap(hostedStateViewAction(titled: "Retry", in: rootView))()
        try await waitUntil {
            self.hasText("No containers connected", in: rootView)
        }
        XCTAssertEqual(attempts, 2)

        viewModel.networks = [network(containerCount: 1)]
        try await waitUntil { tableView.numberOfRows == 1 }
        XCTAssertTrue(hasText("1 container", in: rootView))
        XCTAssertTrue(cellText(in: tableView, column: 1, row: 0).contains("Stopped"))
        XCTAssertEqual(attempts, 3)

        controller?.update(
            loadContainers: loader,
            runningContainerIDs: nil
        )
        XCTAssertTrue(cellText(in: tableView, column: 1, row: 0).contains("—"))
        XCTAssertEqual(attempts, 3)

        controller?.update(
            loadContainers: loader,
            runningContainerIDs: ["container-id"]
        )
        XCTAssertTrue(cellText(in: tableView, column: 1, row: 0).contains("Running"))
        XCTAssertEqual(attempts, 3)

        controller?.update(
            loadContainers: nil,
            runningContainerIDs: ["container-id"]
        )
        XCTAssertTrue(hasText("Docker client unavailable.", in: rootView))

        controller = nil
        XCTAssertNil(weakController)

        viewModel.selectedID = nil
        await Task.yield()
    }

    @MainActor
    private func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }
        return view.subviews.lazy.compactMap { self.findTableView(in: $0) }.first
    }

    @MainActor
    private func cellText(in tableView: NSTableView, column: Int, row: Int) -> String {
        let cell =
            tableView.view(atColumn: column, row: row, makeIfNecessary: true)
            as? NSTableCellView
        return cell?.textField?.stringValue ?? ""
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
    private func hasText(_ text: String, in view: NSView) -> Bool {
        if hostedStateViewDisplays(text, in: view) {
            return true
        }
        if let textField = view as? NSTextField, textField.stringValue == text {
            return true
        }
        return view.subviews.contains { hasText(text, in: $0) }
    }

    private func network(containerCount: Int = 0) -> NetworkViewModel {
        NetworkViewModel(
            id: "network-id",
            name: "frontend",
            driver: "bridge",
            scope: "local",
            createdAt: .distantPast,
            internal: false,
            attachable: false,
            containerCount: containerCount
        )
    }
}

private struct InspectError: LocalizedError {
    var errorDescription: String? {
        "Inspect failed."
    }
}
