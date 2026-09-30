import AppKit
import XCTest

@testable import ArcBox

/// Pins that a snapshot change edits the outline row by row: no `reloadData`,
/// exactly the inserts/removes/moves the change implies, and untouched rows
/// keep their cells, expansion, and selection.
@MainActor
final class ContainersListIncrementalUpdateTests: XCTestCase {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private struct Harness {
        let viewModel: ContainersViewModel
        let controller: ContainersListViewController
        let outlineView: ContainersOutlineView
        let window: NSWindow
    }

    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.close() }
        windows.removeAll()
        super.tearDown()
    }

    // MARK: - T1: presentation-only change

    func testStateFlipInsideGroupUpdatesCellInPlace() async throws {
        let harness = try await makeLoadedHarness(containers: fixtureContainers())
        let outlineView = harness.outlineView
        harness.viewModel.selectedID = "s1"
        try await waitUntil { outlineView.selectedRow == self.row(forContainer: "s1", in: outlineView) }

        let cellBefore = try containerCell("g1-b", in: outlineView)
        XCTAssertEqual(try XCTUnwrap(button("ContainerToggleButton", in: cellBefore)).toolTip, "Stop container")
        let countsBefore = outlineView.updateCounts
        let selectedRowBefore = outlineView.selectedRow

        try await render(harness) {
            harness.viewModel.setContainerRunningState("g1-b", isRunning: false)
        }

        XCTAssertEqual(outlineView.updateCounts, countsBefore)
        let cellAfter = try XCTUnwrap(
            outlineView.view(
                atColumn: 0,
                row: try XCTUnwrap(row(forContainer: "g1-b", in: outlineView)),
                makeIfNecessary: false
            ) as? ContainerTableCellView
        )
        XCTAssertTrue(cellAfter === cellBefore)
        XCTAssertEqual(try XCTUnwrap(button("ContainerToggleButton", in: cellAfter)).toolTip, "Start container")
        XCTAssertEqual(cellAfter.accessibilityLabel(), "g1-b, nginx:latest, Stopped")
        XCTAssertTrue(hasTextField("3/4", in: try cell(forGroup: "g1", in: outlineView)))
        assertGroupsExpanded(["g1", "g2", "g3"], in: harness)
        XCTAssertEqual(outlineView.selectedRow, selectedRowBefore)
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "s1", in: outlineView))
        XCTAssertEqual(harness.viewModel.selectedID, "s1")
        assertOutlineMatchesViewModel(harness)
    }

    // MARK: - T2: structural changes

    func testContainerAddedToGroupInsertsOneRow() async throws {
        let harness = try await makeLoadedHarness(containers: fixtureContainers(), selectedID: "g2-a")
        let outlineView = harness.outlineView
        let countsBefore = outlineView.updateCounts

        try await render(harness) {
            harness.viewModel.containers.append(container(id: "g2-e", state: .running, project: "g2"))
        }

        assertCounts(outlineView, since: countsBefore, inserts: 1, removes: 0, moves: 0)
        XCTAssertNotNil(row(forContainer: "g2-e", in: outlineView))
        assertGroupsExpanded(["g1", "g2", "g3"], in: harness)
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "g2-a", in: outlineView))
        assertOutlineMatchesViewModel(harness)
    }

    func testContainerAddedToCollapsedGroupAppearsOnExpand() async throws {
        let harness = try await makeLoadedHarness(
            containers: fixtureContainers(),
            expandedGroups: ["g1", "g3"]
        )
        let outlineView = harness.outlineView
        let countsBefore = outlineView.updateCounts

        try await render(harness) {
            harness.viewModel.containers.append(container(id: "g2-e", state: .running, project: "g2"))
        }

        XCTAssertEqual(outlineView.updateCounts.reloads, countsBefore.reloads)
        XCTAssertNil(row(forContainer: "g2-e", in: outlineView))
        assertOutlineMatchesViewModel(harness)

        try await render(harness) {
            harness.viewModel.toggleGroup("g2")
        }
        XCTAssertNotNil(row(forContainer: "g2-e", in: outlineView))
        XCTAssertTrue(hasTextField("5/5", in: try cell(forGroup: "g2", in: outlineView)))
        assertOutlineMatchesViewModel(harness)
    }

    func testContainerRemovedFromGroupRemovesOneRow() async throws {
        let harness = try await makeLoadedHarness(containers: fixtureContainers(), selectedID: "s2")
        let outlineView = harness.outlineView
        let countsBefore = outlineView.updateCounts

        try await render(harness) {
            harness.viewModel.containers.removeAll { $0.id == "g3-c" }
        }

        assertCounts(outlineView, since: countsBefore, inserts: 0, removes: 1, moves: 0)
        XCTAssertNil(row(forContainer: "g3-c", in: outlineView))
        assertGroupsExpanded(["g1", "g2", "g3"], in: harness)
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "s2", in: outlineView))
        assertOutlineMatchesViewModel(harness)
    }

    func testStandaloneStartMovesRowBetweenSections() async throws {
        let harness = try await makeLoadedHarness(containers: fixtureContainers(), selectedID: "s1")
        let outlineView = harness.outlineView
        let countsBefore = outlineView.updateCounts
        let movingCell = try containerCell("s6", in: outlineView)

        try await render(harness) {
            harness.viewModel.setContainerRunningState("s6", isRunning: true)
        }

        assertCounts(outlineView, since: countsBefore, inserts: 0, removes: 0, moves: 1)
        let movedRow = try XCTUnwrap(row(forContainer: "s6", in: outlineView))
        XCTAssertLessThan(movedRow, try XCTUnwrap(row(forSection: "Stopped", in: outlineView)))
        let movedCell = try XCTUnwrap(
            outlineView.view(atColumn: 0, row: movedRow, makeIfNecessary: false) as? ContainerTableCellView
        )
        XCTAssertTrue(movedCell === movingCell)
        XCTAssertEqual(try XCTUnwrap(button("ContainerToggleButton", in: movedCell)).toolTip, "Stop container")
        assertGroupsExpanded(["g1", "g2", "g3"], in: harness)
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "s1", in: outlineView))
        assertOutlineMatchesViewModel(harness)
    }

    func testStoppingGroupMovesItAndKeepsItExpanded() async throws {
        let harness = try await makeLoadedHarness(containers: fixtureContainers(), selectedID: "g3-a")
        let outlineView = harness.outlineView
        let countsBefore = outlineView.updateCounts

        try await render(harness) {
            for id in ["g3-a", "g3-b", "g3-c", "g3-d"] {
                harness.viewModel.setContainerRunningState(id, isRunning: false)
            }
        }

        assertCounts(outlineView, since: countsBefore, inserts: 0, removes: 0, moves: 1)
        XCTAssertGreaterThan(
            try XCTUnwrap(row(forGroup: "g3", in: outlineView)),
            try XCTUnwrap(row(forSection: "Stopped", in: outlineView))
        )
        assertGroupsExpanded(["g1", "g2", "g3"], in: harness)
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "g3-a", in: outlineView))
        XCTAssertEqual(harness.viewModel.selectedID, "g3-a")
        assertOutlineMatchesViewModel(harness)
    }

    func testLastStoppedContainerRemovalDropsSection() async throws {
        var containers = fixtureContainers().filter { $0.isRunning }
        containers.append(container(id: "sleeping", state: .stopped))
        let harness = try await makeLoadedHarness(containers: containers, selectedID: "s1")
        let outlineView = harness.outlineView
        XCTAssertNotNil(row(forSection: "Stopped", in: outlineView))
        let countsBefore = outlineView.updateCounts

        try await render(harness) {
            harness.viewModel.containers.removeAll { $0.id == "sleeping" }
        }

        assertCounts(outlineView, since: countsBefore, inserts: 0, removes: 2, moves: 0)
        XCTAssertNil(row(forSection: "Stopped", in: outlineView))
        assertGroupsExpanded(["g1", "g2", "g3"], in: harness)
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "s1", in: outlineView))
        assertOutlineMatchesViewModel(harness)
    }

    func testFirstStoppedContainerAddsSection() async throws {
        let harness = try await makeLoadedHarness(
            containers: fixtureContainers().filter { $0.isRunning },
            selectedID: "g1-a"
        )
        let outlineView = harness.outlineView
        XCTAssertNil(row(forSection: "Stopped", in: outlineView))
        let countsBefore = outlineView.updateCounts

        try await render(harness) {
            harness.viewModel.containers.append(container(id: "sleeping", state: .stopped))
        }

        assertCounts(outlineView, since: countsBefore, inserts: 2, removes: 0, moves: 0)
        XCTAssertNotNil(row(forSection: "Stopped", in: outlineView))
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "g1-a", in: outlineView))
        assertOutlineMatchesViewModel(harness)
    }

    // MARK: - T5: stress

    func testSixtyMutationsStayUnderBudget() async throws {
        var containers: [ContainerViewModel] = []
        for group in 1...4 {
            for index in 0..<5 {
                containers.append(
                    container(id: "p\(group)-\(index)", state: .running, project: "p\(group)")
                )
            }
        }
        for index in 0..<20 {
            containers.append(container(id: "solo-\(index)", state: index < 10 ? .running : .stopped))
        }
        let harness = try await makeLoadedHarness(
            containers: containers,
            expandedGroups: ["p1", "p2", "p3", "p4"],
            selectedID: "solo-0"
        )
        let outlineView = harness.outlineView
        XCTAssertEqual(outlineView.numberOfRows, 46)
        let reloadsBefore = outlineView.updateCounts.reloads

        // The first batch update pays AppKit's one-time setup (about 50 ms
        // measured); it is not what a Docker event costs, so it is not timed.
        try await render(harness) {
            harness.viewModel.setTransitioning("p1-0", true)
        }

        var generator = SeededGenerator(state: 0x5EED)
        let clock = ContinuousClock()
        var durations: [Duration] = []
        for iteration in 0..<60 {
            let target = containers.randomElement(using: &generator)!
            let start = clock.now
            try await render(harness) {
                switch iteration % 3 {
                case 0, 1:
                    let current = try XCTUnwrap(harness.viewModel.containers.first { $0.id == target.id })
                    harness.viewModel.setContainerRunningState(target.id, isRunning: !current.isRunning)
                default:
                    // Ports change together with the transition flag: `ContainerViewModel ==`
                    // ignores ports, so a ports-only write never reaches observers.
                    harness.viewModel.updateContainer(target.id) { current in
                        var replacement = self.container(
                            id: current.id,
                            state: current.state,
                            project: current.composeProject,
                            ports: [
                                PortMapping(
                                    hostPort: UInt16(10_000 + iteration),
                                    containerPort: 80,
                                    protocol: "tcp"
                                )
                            ]
                        )
                        replacement.isTransitioning = !current.isTransitioning
                        current = replacement
                    }
                }
            }
            outlineView.layoutSubtreeIfNeeded()
            durations.append(clock.now - start)
        }

        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        let max = sorted[sorted.count - 1]
        let slowest = zip(durations.indices, durations).sorted { $0.1 > $1.1 }.prefix(3)
            .map { "#\($0.0) \($0.1)" }
        print("PERF snapshot mutation x60: median \(median), max \(max), slowest \(slowest)")
        // The reload count is the guard: a regression to whole-list reloads is
        // structural, not a timing outlier. The wall-clock bounds only fence off
        // the hang class — locally the median is ~0.5 ms and the maximum ~4 ms,
        // and CI runners are several times slower and noisier than that.
        XCTAssertEqual(outlineView.updateCounts.reloads, reloadsBefore)
        XCTAssertLessThan(median, .milliseconds(10))
        XCTAssertLessThan(max, .milliseconds(100))
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "solo-0", in: outlineView))
        assertOutlineMatchesViewModel(harness)
    }

    // MARK: - Blank-list investigation

    func testRowsSurviveEmptyStateRoundTrip() async throws {
        let containers = fixtureContainers()
        let harness = try await makeLoadedHarness(containers: containers)
        let outlineView = harness.outlineView
        let scrollView = try XCTUnwrap(outlineView.enclosingScrollView)

        harness.viewModel.containers = []
        try await waitUntil { scrollView.isHidden }

        harness.viewModel.containers = containers
        try await waitUntil { !scrollView.isHidden && outlineView.numberOfRows == self.expectedRowCount(harness) }
        assertRowsAreMaterialized(harness)
        assertOutlineMatchesViewModel(harness)
    }

    func testBurstOfMutationsInOneTurnRendersFinalState() async throws {
        let harness = try await makeLoadedHarness(containers: fixtureContainers(), selectedID: "s3")
        let outlineView = harness.outlineView
        let reloadsBefore = outlineView.updateCounts.reloads

        try await render(harness) {
            for iteration in 0..<50 {
                let id = iteration.isMultiple(of: 2) ? "s\(iteration % 10 + 1)" : "g\(iteration % 3 + 1)-a"
                harness.viewModel.setContainerRunningState(id, isRunning: iteration % 4 < 2)
            }
        }
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(outlineView.updateCounts.reloads, reloadsBefore)
        assertRowsAreMaterialized(harness)
        XCTAssertEqual(outlineView.selectedRow, row(forContainer: "s3", in: outlineView))
        assertOutlineMatchesViewModel(harness)
    }

    func testStaleSelectionAndExpansionDoNotBlankTheList() async throws {
        let viewModel = ContainersViewModel()
        viewModel.loadState = .loaded
        viewModel.containers = fixtureContainers()
        viewModel.expandedGroups = ["g1", "g2", "g3", "vanished-project"]
        viewModel.selectedID = "ghost"
        let harness = try await makeHarness(viewModel: viewModel)

        try await waitUntil { viewModel.selectedID == nil }
        XCTAssertEqual(harness.outlineView.selectedRow, -1)
        XCTAssertEqual(harness.outlineView.numberOfRows, expectedRowCount(harness))
        assertRowsAreMaterialized(harness)
        assertOutlineMatchesViewModel(harness)
    }

    // MARK: - Harness

    private func makeLoadedHarness(
        containers: [ContainerViewModel],
        expandedGroups: Set<String> = ["g1", "g2", "g3"],
        selectedID: String? = nil
    ) async throws -> Harness {
        let viewModel = ContainersViewModel()
        viewModel.loadState = .loaded
        viewModel.expandedGroups = expandedGroups
        viewModel.containers = containers
        viewModel.selectedID = selectedID
        let harness = try await makeHarness(viewModel: viewModel)
        if let selectedID {
            try await waitUntil {
                harness.outlineView.selectedRow == self.row(forContainer: selectedID, in: harness.outlineView)
            }
        }
        return harness
    }

    private func makeHarness(viewModel: ContainersViewModel) async throws -> Harness {
        let controller = ContainersListViewController(
            viewModel: viewModel,
            loadingTitle: "Loading containers…",
            useDNS: false,
            actions: .init(
                retry: {},
                select: { _ in },
                toggle: { _ in },
                delete: { _ in },
                toggleGroup: { _, _ in },
                deleteGroup: { _, _ in }
            )
        )
        // Ordered in, but parked far off every screen: AppKit only materializes
        // row views for a table that is part of a displayed window.
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 600, height: 2_400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        // Assigning the controller sizes the window to its zero-sized view.
        window.setContentSize(NSSize(width: 600, height: 2_400))
        window.orderBack(nil)
        windows.append(window)
        let outlineView = try XCTUnwrap(findOutlineView(in: controller.view))
        let harness = Harness(
            viewModel: viewModel,
            controller: controller,
            outlineView: outlineView,
            window: window
        )
        try await waitUntil { outlineView.numberOfRows == self.expectedRowCount(harness) }
        window.layoutIfNeeded()
        window.display()
        return harness
    }

    /// Runs `mutation` and waits until the controller has rendered once more.
    private func render(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line,
        after mutation: @MainActor () throws -> Void
    ) async throws {
        var didRender = false
        harness.controller.renderObserver = { didRender = true }
        defer { harness.controller.renderObserver = nil }
        let renderCountBefore = harness.controller.renderCount
        try mutation()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !didRender, clock.now < deadline {
            try await Task.sleep(for: .microseconds(100))
        }
        XCTAssertTrue(
            didRender,
            "no render within 2 s (renderCount \(renderCountBefore) -> \(harness.controller.renderCount))",
            file: file,
            line: line
        )
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out waiting for AppKit observation update", file: file, line: line)
    }

    // MARK: - Assertions

    private func assertCounts(
        _ outlineView: ContainersOutlineView,
        since before: ContainersOutlineView.UpdateCounts,
        inserts: Int,
        removes: Int,
        moves: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let counts = outlineView.updateCounts
        XCTAssertEqual(counts.reloads, before.reloads, "reloadData was called", file: file, line: line)
        XCTAssertEqual(counts.inserts - before.inserts, inserts, "inserts", file: file, line: line)
        XCTAssertEqual(counts.removes - before.removes, removes, "removes", file: file, line: line)
        XCTAssertEqual(counts.moves - before.moves, moves, "moves", file: file, line: line)
    }

    private func assertGroupsExpanded(
        _ projects: [String],
        in harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for project in projects {
            guard let row = row(forGroup: project, in: harness.outlineView) else {
                XCTFail("group \(project) is not in the outline", file: file, line: line)
                continue
            }
            let item = harness.outlineView.item(atRow: row)
            XCTAssertTrue(harness.outlineView.isItemExpanded(item), "\(project) collapsed", file: file, line: line)
        }
        XCTAssertEqual(harness.viewModel.expandedGroups, Set(projects), file: file, line: line)
    }

    /// The outline's rows must equal the snapshot the view model implies, in
    /// order, with expanded groups' children inline.
    private func assertOutlineMatchesViewModel(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = expectedVisibleIDs(harness)
        let actual = (0..<harness.outlineView.numberOfRows).map { row in
            (harness.outlineView.item(atRow: row) as? ContainerListNode)?.id
        }
        XCTAssertEqual(actual, expected.map(Optional.some), file: file, line: line)
    }

    private func assertRowsAreMaterialized(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let outlineView = harness.outlineView
        harness.window.layoutIfNeeded()
        harness.window.display()
        XCTAssertGreaterThan(outlineView.numberOfRows, 0, file: file, line: line)
        var totalHeight: CGFloat = 0
        for row in 0..<outlineView.numberOfRows {
            let rect = outlineView.rect(ofRow: row)
            XCTAssertGreaterThan(rect.height, 0, "row \(row) has no height", file: file, line: line)
            totalHeight += rect.height
            let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView
            XCTAssertNotNil(cell, "row \(row) has no cell view", file: file, line: line)
            XCTAssertFalse(cell?.textField?.stringValue.isEmpty ?? true, "row \(row) is blank", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(outlineView.frame.height, totalHeight, file: file, line: line)
    }

    private func expectedVisibleIDs(_ harness: Harness) -> [ContainerListNodeID] {
        var ids: [ContainerListNodeID] = []
        for root in ContainerListSnapshot(viewModel: harness.viewModel).roots {
            ids.append(root.id)
            if case .compose(let project, _) = root, harness.viewModel.expandedGroups.contains(project) {
                ids.append(contentsOf: root.childPresentations.map(\.id))
            }
        }
        return ids
    }

    private func expectedRowCount(_ harness: Harness) -> Int {
        expectedVisibleIDs(harness).count
    }

    // MARK: - Lookup

    private func findOutlineView(in view: NSView) -> ContainersOutlineView? {
        if let outlineView = view as? ContainersOutlineView {
            return outlineView
        }
        return view.subviews.lazy.compactMap { self.findOutlineView(in: $0) }.first
    }

    private func row(of id: ContainerListNodeID, in outlineView: NSOutlineView) -> Int? {
        (0..<outlineView.numberOfRows).first { row in
            (outlineView.item(atRow: row) as? ContainerListNode)?.id == id
        }
    }

    private func row(forContainer id: String, in outlineView: NSOutlineView) -> Int? {
        row(of: .container(id), in: outlineView)
    }

    private func row(forGroup project: String, in outlineView: NSOutlineView) -> Int? {
        row(of: .compose(project), in: outlineView)
    }

    private func row(forSection title: String, in outlineView: NSOutlineView) -> Int? {
        row(of: .section(title), in: outlineView)
    }

    private func containerCell(
        _ id: String,
        in outlineView: NSOutlineView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ContainerTableCellView {
        let row = try XCTUnwrap(row(forContainer: id, in: outlineView), file: file, line: line)
        let view = try XCTUnwrap(
            outlineView.view(atColumn: 0, row: row, makeIfNecessary: true),
            file: file,
            line: line
        )
        return try XCTUnwrap(
            view as? ContainerTableCellView,
            "row \(row) holds \(type(of: view))",
            file: file,
            line: line
        )
    }

    private func cell(forGroup project: String, in outlineView: NSOutlineView) throws -> NSView {
        let row = try XCTUnwrap(row(forGroup: project, in: outlineView))
        return try XCTUnwrap(outlineView.view(atColumn: 0, row: row, makeIfNecessary: true))
    }

    private func button(_ identifier: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.identifier == NSUserInterfaceItemIdentifier(identifier) {
            return button
        }
        return view.subviews.lazy.compactMap { self.button(identifier, in: $0) }.first
    }

    private func hasTextField(_ text: String, in view: NSView) -> Bool {
        if let textField = view as? NSTextField, textField.stringValue == text {
            return true
        }
        return view.subviews.contains { hasTextField(text, in: $0) }
    }

    // MARK: - Fixtures

    /// Three compose groups of four running containers plus ten standalone
    /// containers, half of them stopped.
    private func fixtureContainers() -> [ContainerViewModel] {
        var containers: [ContainerViewModel] = []
        for group in ["g1", "g2", "g3"] {
            for suffix in ["a", "b", "c", "d"] {
                containers.append(container(id: "\(group)-\(suffix)", state: .running, project: group))
            }
        }
        for index in 1...10 {
            containers.append(container(id: "s\(index)", state: index <= 5 ? .running : .stopped))
        }
        return containers
    }

    private func container(
        id: String,
        state: ContainerState,
        project: String? = nil,
        ports: [PortMapping] = []
    ) -> ContainerViewModel {
        ContainerViewModel(
            id: id,
            name: id,
            image: "nginx:latest",
            state: state,
            ports: ports,
            createdAt: .distantPast,
            composeProject: project,
            composeService: project == nil ? nil : id,
            labels: [:],
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        )
    }
}
