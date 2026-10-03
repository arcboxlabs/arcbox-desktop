import XCTest

@testable import ArcBox

/// Covers the join between the daemon's cgroup stats and Docker's Compose
/// labels: which rows group, what a project's totals mean, and how the table's
/// sort reaches rows nested under a project.
final class ActivityRowGroupingTests: XCTestCase {

    func testContainersWithoutAProjectStayAtTheTopLevel() throws {
        let groups = ActivityRowGrouping.groups(
            for: [row(id: "a"), row(id: "b")],
            projects: ["a": "web"],
            sortedBy: []
        )

        XCTAssertEqual(
            groups.count, 2,
            "the project and the loose container are both top-level rows")
        let standalone = try XCTUnwrap(groups.first { $0.summary.containerID == "b" })
        XCTAssertEqual(standalone.children, [], "a project-less container should not gain children")
    }

    /// A container the Engine has not reported yet has no project, and must not
    /// be swept into a shared bucket that would claim a relationship.
    func testUnknownContainersAreNotBucketedTogether() {
        let groups = ActivityRowGrouping.groups(
            for: [row(id: "a"), row(id: "b")],
            projects: [:],
            sortedBy: []
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.children.isEmpty })
        XCTAssertTrue(groups.allSatisfy { !$0.summary.isProject })
    }

    func testProjectTotalsSumItsMembers() throws {
        let groups = ActivityRowGrouping.groups(
            for: [
                row(id: "a", cpu: 12.5, memory: 100, disk: (1, 2), network: (3, 4), pids: 7),
                row(id: "b", cpu: 7.5, memory: 200, disk: (10, 20), network: (30, 40), pids: 11),
            ],
            projects: ["a": "web", "b": "web"],
            sortedBy: []
        )

        let project = try XCTUnwrap(groups.first)
        XCTAssertEqual(project.summary.cpuPercent, 20)
        XCTAssertEqual(project.summary.memoryCurrentBytes, 300)
        XCTAssertEqual(project.summary.diskReadBytesPerSecond, 11)
        XCTAssertEqual(project.summary.diskWriteBytesPerSecond, 22)
        XCTAssertEqual(project.summary.networkReceiveBytesPerSecond, 33)
        XCTAssertEqual(project.summary.networkTransmitBytesPerSecond, 44)
        XCTAssertEqual(project.summary.pids, 18)
        XCTAssertEqual(project.children.count, 2)
    }

    func testProjectMemoryLimitSumsOnlyWhenEveryMemberIsLimited() {
        let limited = ActivityRowGrouping.groups(
            for: [row(id: "a", memoryLimit: 512), row(id: "b", memoryLimit: 256)],
            projects: ["a": "web", "b": "web"],
            sortedBy: []
        )
        XCTAssertEqual(limited.first?.summary.memoryLimitBytes, 768)

        let mixed = ActivityRowGrouping.groups(
            for: [row(id: "a", memoryLimit: 512), row(id: "b", memoryLimit: 0)],
            projects: ["a": "web", "b": "web"],
            sortedBy: []
        )
        XCTAssertEqual(
            mixed.first?.summary.memoryLimitBytes, 0,
            "one unlimited member makes the project's ceiling unknowable, not 512")
    }

    func testSortReachesBothTheProjectsAndTheirMembers() {
        let groups = ActivityRowGrouping.groups(
            for: [
                row(id: "quiet", cpu: 1),
                row(id: "busy-a", cpu: 30),
                row(id: "busy-b", cpu: 60),
            ],
            projects: ["busy-a": "web", "busy-b": "web"],
            sortedBy: [KeyPathComparator(\ActivityRow.cpuPercent, order: .reverse)]
        )

        XCTAssertEqual(
            groups.map(\.summary.title), ["web", "quiet"],
            "the project totals 90% and outranks the standalone container")
        XCTAssertEqual(
            groups.first?.children.map(\.title), ["busy-b", "busy-a"],
            "members sort by the same comparator as the groups")
    }

    /// The CPU column sorts on the whole percent it displays, so the fractions
    /// an idle container's counter jitters through cannot reorder rows that
    /// all read the same.
    func testCPUSortIgnoresSubPercentJitter() {
        let byDisplayedCPU = [KeyPathComparator(\ActivityRow.displayedCPUPercent, order: .reverse)]
        let before = ActivityRowGrouping.groups(
            for: [row(id: "c", cpu: 0.04), row(id: "a", cpu: 0.31), row(id: "b", cpu: 0.12)],
            projects: [:],
            sortedBy: byDisplayedCPU
        )
        let after = ActivityRowGrouping.groups(
            for: [row(id: "c", cpu: 0.27), row(id: "a", cpu: 0.02), row(id: "b", cpu: 0.4)],
            projects: [:],
            sortedBy: byDisplayedCPU
        )

        XCTAssertEqual(before.map(\.summary.title), ["a", "b", "c"], "all three read 0%, so title decides")
        XCTAssertEqual(after.map(\.summary.title), ["a", "b", "c"], "and a new sample cannot shuffle them")
        XCTAssertEqual(
            ActivityRowGrouping.groups(
                for: [row(id: "a", cpu: 0.4), row(id: "b", cpu: 1.6)],
                projects: [:],
                sortedBy: byDisplayedCPU
            ).map(\.summary.title),
            ["b", "a"],
            "a difference the column shows still sorts")
    }

    /// Rows the comparators leave tied keep a fixed order — by title, then by
    /// ID — inside a project as well as at the top level.
    func testTiedRowsOrderByTitleThenID() {
        let groups = ActivityRowGrouping.groups(
            for: [row(id: "3", title: "web"), row(id: "2", title: "api"), row(id: "1", title: "web")],
            projects: ["1": "stack", "2": "stack", "3": "stack"],
            sortedBy: [KeyPathComparator(\ActivityRow.pids)]
        )

        XCTAssertEqual(groups.first?.children.map(\.id), ["2", "1", "3"])
    }

    /// Selection and the table's saved disclosure state are keyed by ID, so a
    /// project must never be able to impersonate a container.
    func testProjectIDsCannotCollideWithContainerIDs() {
        let summary = ActivityRow.project(named: "web", totalling: [row(id: "a")])

        XCTAssertNotEqual(summary.id, "web")
        XCTAssertNil(summary.containerID)
        XCTAssertFalse(
            summary.id.allSatisfy(\.isHexDigit),
            "a container ID is hex, so the project prefix has to break that")
    }

    func testFilteringTemporarilyExpandsGroupsAndRestoresTheirState() {
        var state = ActivityRowDisclosureState()
        state.setExpanded(true, for: "project:expanded", isFiltering: false)

        XCTAssertFalse(state.isExpanded("project:collapsed", isFiltering: false))
        XCTAssertTrue(state.isExpanded("project:expanded", isFiltering: false))
        XCTAssertTrue(state.isExpanded("project:collapsed", isFiltering: true))
        XCTAssertTrue(state.isExpanded("project:expanded", isFiltering: true))

        state.setExpanded(false, for: "project:expanded", isFiltering: true)
        XCTAssertFalse(state.isExpanded("project:collapsed", isFiltering: false))
        XCTAssertTrue(state.isExpanded("project:expanded", isFiltering: false))
    }

    // MARK: - Fixtures

    private func row(
        id: String,
        title: String? = nil,
        cpu: Double = 0,
        memory: UInt64 = 0,
        memoryLimit: UInt64 = 0,
        disk: (read: Double, write: Double) = (0, 0),
        network: (receive: Double, transmit: Double) = (0, 0),
        pids: UInt32 = 0
    ) -> ActivityRow {
        ActivityRow(
            id: id,
            title: title ?? id,
            kind: .container(id: id),
            cpuPercent: cpu,
            memoryCurrentBytes: memory,
            memoryLimitBytes: memoryLimit,
            diskReadBytesPerSecond: disk.read,
            diskWriteBytesPerSecond: disk.write,
            networkReceiveBytesPerSecond: network.receive,
            networkTransmitBytesPerSecond: network.transmit,
            pids: pids
        )
    }
}
