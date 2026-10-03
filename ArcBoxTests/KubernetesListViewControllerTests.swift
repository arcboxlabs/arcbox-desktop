import AppKit
import XCTest

@testable import ArcBox

final class KubernetesListViewControllerTests: XCTestCase {
    @MainActor
    func testPodsStatesRetrySearchAndSelection() async throws {
        let state = KubernetesState(lifecycle: .ready)
        let viewModel = PodsViewModel()
        viewModel.selectedID = "stale"
        var didRetry = false
        let controller = PodsListViewController(
            state: state,
            viewModel: viewModel,
            canControl: true,
            onCheckStatus: {},
            onStart: {},
            onStop: {},
            onRetryStreams: { didRetry = true }
        )
        let rootView = controller.view
        let tableView = try XCTUnwrap(findTableView(in: rootView))
        XCTAssertEqual(viewModel.selectedID, "stale")
        viewModel.selectedID = nil

        XCTAssertFalse(hasText("Loading pods…", in: rootView))
        let loadingPlaceholder = try XCTUnwrap(hostedStateView(in: rootView))
        guard case .loading(let loadingTitle) = loadingPlaceholder.rootView.state else {
            return XCTFail("Expected the hosted loading state")
        }
        XCTAssertNil(loadingTitle)

        viewModel.streamPhase = .live
        try await waitUntil { self.hasText("No pods", in: rootView) }
        let noPodsLabel = try XCTUnwrap(textField(titled: "No pods", in: rootView))
        XCTAssertEqual(noPodsLabel.font?.pointSize, 13)
        XCTAssertEqual(noPodsLabel.textColor, .secondaryLabelColor)

        viewModel.streamPhase = .reconnecting(attempt: 2, lastError: "Connection lost")
        try await waitUntil {
            hostedStateViewAction(titled: "Retry", in: rootView) != nil
        }
        try XCTUnwrap(hostedStateViewAction(titled: "Retry", in: rootView))()
        XCTAssertTrue(didRetry)

        viewModel.pods = [
            pod(id: "alpha", name: "alpha"),
            pod(id: "beta", name: "beta"),
        ]
        viewModel.streamPhase = .live
        try await waitUntil { tableView.numberOfRows == 2 }

        viewModel.selectedID = "beta"
        try await waitUntil { tableView.selectedRow == 1 }
        let betaCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: 1, makeIfNecessary: true)
                as? NSTableCellView
        )
        betaCell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        betaCell.layoutSubtreeIfNeeded()
        let podIconBox = try XCTUnwrap(ancestorBox(of: betaCell.imageView))
        let podLabels = try XCTUnwrap(betaCell.textField?.superview as? NSStackView)
        let podStatusDot = try XCTUnwrap(
            view(identifier: "PodStatusDot", in: betaCell)
        )
        XCTAssertEqual(podIconBox.fillColor, AppColors.iconBackgroundNSColor)
        XCTAssertEqual(podIconBox.frame.minX, 16, accuracy: 0.5)
        XCTAssertEqual(podLabels.frame.minX - podIconBox.frame.maxX, 12, accuracy: 0.5)
        XCTAssertEqual(betaCell.bounds.maxX - podStatusDot.frame.maxX, 16, accuracy: 0.5)
        XCTAssertEqual(betaCell.imageView?.contentTintColor, .secondaryLabelColor)

        viewModel.searchText = "alpha"
        try await waitUntil { tableView.numberOfRows == 1 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedPod?.id, "beta")

        viewModel.searchText = "missing"
        try await waitUntil {
            tableView.numberOfRows == 0
                && self.hasText("No Results", in: rootView)
        }
        XCTAssertEqual(viewModel.selectedID, "beta")
        viewModel.streamPhase = .reconnecting(attempt: 3, lastError: nil)
        try await waitUntil {
            self.hasText(
                "No pods match “missing”.\nReconnecting to Kubernetes (attempt 3)",
                in: rootView
            )
        }

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == 1 }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "alpha")

        viewModel.pods.removeAll { $0.id == "alpha" }
        XCTAssertNil(viewModel.selectedID)
        try await waitUntil { tableView.selectedRow == -1 }
    }

    @MainActor
    func testServicesDisabledActionRowsAndSearch() async throws {
        let disabledState = KubernetesState(lifecycle: .disabled)
        let disabledViewModel = ServicesViewModel()
        var didStart = false
        let disabledController = ServicesListViewController(
            state: disabledState,
            viewModel: disabledViewModel,
            canControl: true,
            onCheckStatus: {},
            onStart: { didStart = true },
            onStop: {},
            onRetryStreams: {}
        )
        let disabledRoot = disabledController.view
        disabledRoot.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        disabledRoot.layoutSubtreeIfNeeded()

        let disabledIcon = try XCTUnwrap(
            visibleView(identifier: "KubernetesDisabledIcon", in: disabledRoot)
        )
        let disabledTitle = try XCTUnwrap(
            textField(titled: "Kubernetes Disabled", in: disabledRoot)
        )
        let turnOnButton = try XCTUnwrap(visibleButton(titled: "Turn On", in: disabledRoot))
        XCTAssertEqual(disabledIcon.frame.width, 48, accuracy: 0.5)
        XCTAssertEqual((disabledIcon.superview as? NSStackView)?.spacing, 20)
        XCTAssertEqual(
            disabledTitle.font,
            NSFont.systemFont(ofSize: 20, weight: .medium)
        )
        XCTAssertEqual(disabledTitle.textColor, .secondaryLabelColor)
        XCTAssertEqual(turnOnButton.controlSize, .regular)
        XCTAssertEqual(turnOnButton.bezelStyle, .rounded)
        XCTAssertEqual(turnOnButton.bezelColor, .controlAccentColor)
        turnOnButton.performClick(nil)
        XCTAssertTrue(didStart)

        let readyState = KubernetesState(lifecycle: .ready)
        let viewModel = ServicesViewModel()
        viewModel.services = [
            service(id: "api", name: "api"),
            service(id: "database", name: "database"),
        ]
        viewModel.selectedID = "stale"
        viewModel.streamPhase = .live
        let controller = ServicesListViewController(
            state: readyState,
            viewModel: viewModel,
            canControl: true,
            onCheckStatus: {},
            onStart: {},
            onStop: {},
            onRetryStreams: {}
        )
        let rootView = controller.view
        let tableView = try XCTUnwrap(findTableView(in: rootView))

        XCTAssertEqual(viewModel.selectedID, "stale")
        viewModel.selectedID = nil
        XCTAssertEqual(tableView.numberOfRows, 2)
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "database")
        let selectedCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: 1, makeIfNecessary: true)
                as? NSTableCellView
        )
        selectedCell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        selectedCell.layoutSubtreeIfNeeded()
        let serviceIconBox = try XCTUnwrap(ancestorBox(of: selectedCell.imageView))
        let serviceLabels = try XCTUnwrap(selectedCell.textField?.superview as? NSStackView)
        XCTAssertEqual(serviceIconBox.fillColor, AppColors.iconBackgroundNSColor)
        XCTAssertEqual(serviceIconBox.frame.minX, 16, accuracy: 0.5)
        XCTAssertEqual(
            serviceLabels.frame.minX - serviceIconBox.frame.maxX,
            12,
            accuracy: 0.5
        )
        XCTAssertEqual(
            selectedCell.bounds.maxX - serviceLabels.frame.maxX,
            16,
            accuracy: 0.5
        )
        XCTAssertEqual(selectedCell.imageView?.contentTintColor, .secondaryLabelColor)

        viewModel.searchText = "api"
        try await waitUntil { tableView.numberOfRows == 1 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedService?.id, "database")

        viewModel.searchText = "missing"
        try await waitUntil {
            tableView.numberOfRows == 0
                && self.hasText("No Results", in: rootView)
        }

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == 1 }
        viewModel.services.removeAll { $0.id == "database" }
        XCTAssertNil(viewModel.selectedID)
        try await waitUntil { tableView.selectedRow == -1 }
    }

    @MainActor
    func testStartingStartFailureAndEmptyServicesMatchLegacyPresentation() throws {
        let startingController = PodsListViewController(
            state: KubernetesState(lifecycle: .starting),
            viewModel: PodsViewModel(),
            canControl: true,
            onCheckStatus: {},
            onStart: {},
            onStop: {},
            onRetryStreams: {}
        )
        let startingRoot = startingController.view
        XCTAssertTrue(hasText("Starting Kubernetes…", in: startingRoot))
        let progress = try XCTUnwrap(
            visibleView(identifier: "KubernetesDisabledProgress", in: startingRoot)
                as? NSProgressIndicator
        )
        XCTAssertEqual(progress.controlSize, .regular)

        var didRetry = false
        let failedController = ServicesListViewController(
            state: KubernetesState(lifecycle: .failed(.start, "Kubernetes did not start.")),
            viewModel: ServicesViewModel(),
            canControl: true,
            onCheckStatus: {},
            onStart: { didRetry = true },
            onStop: {},
            onRetryStreams: {}
        )
        let failedRoot = failedController.view
        let errorLabel = try XCTUnwrap(
            textField(titled: "Kubernetes did not start.", in: failedRoot)
        )
        XCTAssertEqual(errorLabel.font?.pointSize, 12)
        XCTAssertEqual(errorLabel.textColor, .systemRed)
        try XCTUnwrap(visibleButton(titled: "Retry", in: failedRoot)).performClick(nil)
        XCTAssertTrue(didRetry)

        let loadingServicesController = ServicesListViewController(
            state: KubernetesState(lifecycle: .ready),
            viewModel: ServicesViewModel(),
            canControl: true,
            onCheckStatus: {},
            onStart: {},
            onStop: {},
            onRetryStreams: {}
        )
        let loadingServicesRoot = loadingServicesController.view
        XCTAssertFalse(hasText("Loading services…", in: loadingServicesRoot))
        let loadingServicesPlaceholder = try XCTUnwrap(
            hostedStateView(in: loadingServicesRoot)
        )
        guard case .loading(let loadingTitle) = loadingServicesPlaceholder.rootView.state else {
            return XCTFail("Expected the hosted loading state")
        }
        XCTAssertNil(loadingTitle)

        let emptyServicesModel = ServicesViewModel()
        emptyServicesModel.streamPhase = .live
        let emptyServicesController = ServicesListViewController(
            state: KubernetesState(lifecycle: .ready),
            viewModel: emptyServicesModel,
            canControl: true,
            onCheckStatus: {},
            onStart: {},
            onStop: {},
            onRetryStreams: {}
        )
        let emptyServicesLabel = try XCTUnwrap(
            textField(titled: "No services", in: emptyServicesController.view)
        )
        XCTAssertEqual(emptyServicesLabel.font?.pointSize, 13)
        XCTAssertEqual(emptyServicesLabel.textColor, .secondaryLabelColor)
    }

    @MainActor
    func testObservationDoesNotRetainControllers() async {
        let state = KubernetesState(lifecycle: .ready)
        let podsModel = PodsViewModel()
        let servicesModel = ServicesViewModel()
        weak var weakPodsController: PodsListViewController?
        weak var weakServicesController: ServicesListViewController?

        autoreleasepool {
            var podsController: PodsListViewController? = PodsListViewController(
                state: state,
                viewModel: podsModel,
                canControl: true,
                onCheckStatus: {},
                onStart: {},
                onStop: {},
                onRetryStreams: {}
            )
            var servicesController: ServicesListViewController? = ServicesListViewController(
                state: state,
                viewModel: servicesModel,
                canControl: true,
                onCheckStatus: {},
                onStart: {},
                onStop: {},
                onRetryStreams: {}
            )
            _ = podsController?.view
            _ = servicesController?.view
            weakPodsController = podsController
            weakServicesController = servicesController
            podsController = nil
            servicesController = nil
        }

        XCTAssertNil(weakPodsController)
        XCTAssertNil(weakServicesController)
        podsModel.searchText = ""
        servicesModel.searchText = ""
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
        return view.subviews.lazy.compactMap {
            self.findTableView(in: $0)
        }.first
    }

    @MainActor
    private func visibleButton(titled title: String, in view: NSView) -> NSButton? {
        guard !view.isHiddenOrHasHiddenAncestor else { return nil }
        if let button = view as? NSButton, button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap {
            self.visibleButton(titled: title, in: $0)
        }.first
    }

    @MainActor
    private func hasText(_ text: String, in view: NSView) -> Bool {
        guard !view.isHiddenOrHasHiddenAncestor else { return false }
        if hostedStateViewDisplays(text, in: view) {
            return true
        }
        if let textField = view as? NSTextField, textField.stringValue == text {
            return true
        }
        return view.subviews.contains { self.hasText(text, in: $0) }
    }

    @MainActor
    private func textField(titled title: String, in view: NSView) -> NSTextField? {
        guard !view.isHiddenOrHasHiddenAncestor else { return nil }
        if let textField = view as? NSTextField, textField.stringValue == title {
            return textField
        }
        return view.subviews.lazy.compactMap {
            self.textField(titled: title, in: $0)
        }.first
    }

    @MainActor
    private func visibleView(identifier: String, in view: NSView) -> NSView? {
        guard !view.isHiddenOrHasHiddenAncestor else { return nil }
        if view.identifier == NSUserInterfaceItemIdentifier(identifier) {
            return view
        }
        return view.subviews.lazy.compactMap {
            self.visibleView(identifier: identifier, in: $0)
        }.first
    }

    @MainActor
    private func view(identifier: String, in view: NSView) -> NSView? {
        if view.identifier == NSUserInterfaceItemIdentifier(identifier) {
            return view
        }
        return view.subviews.lazy.compactMap {
            self.view(identifier: identifier, in: $0)
        }.first
    }

    @MainActor
    private func ancestorBox(of view: NSView?) -> NSBox? {
        guard let superview = view?.superview else { return nil }
        return superview as? NSBox ?? ancestorBox(of: superview)
    }

    private func pod(id: String, name: String) -> PodViewModel {
        PodViewModel(
            id: id,
            name: name,
            namespace: "default",
            phase: .running,
            containerCount: 1,
            readyCount: 1,
            restartCount: 0,
            createdAt: .distantPast
        )
    }

    private func service(id: String, name: String) -> ServiceViewModel {
        ServiceViewModel(
            id: id,
            name: name,
            namespace: "default",
            type: .clusterIP,
            clusterIP: "10.0.0.1",
            ports: [],
            createdAt: .distantPast
        )
    }
}
