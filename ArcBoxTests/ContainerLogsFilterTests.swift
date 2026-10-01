import DockerClient
import XCTest

@testable import ArcBox

/// `filteredEntries` is maintained incrementally; these tests hold it to the
/// full rescan it replaces, through every way the buffer and the filters change.
@MainActor
final class ContainerLogsFilterTests: XCTestCase {
    func testFilteredEntriesMatchAFullRescanThroughAppendsTrimsAndFilterChanges() throws {
        let model = ContainerLogsModel()
        var next = 0
        model.append(ContainerLogsFixtures.lines(from: &next, count: 600))

        // Unfiltered, the buffer itself is the result.
        XCTAssertEqual(model.filteredEntries.map(\.id), model.logEntries.map(\.id))

        for (search, stream) in Self.filters {
            model.searchText = search
            model.streamFilter = stream
            assertMatchesRescan(model, "after switching to \(search.debugDescription)/\(stream)")

            for _ in 0..<5 {
                model.append(ContainerLogsFixtures.lines(from: &next, count: 10))
                assertMatchesRescan(model, "after a batch under \(search.debugDescription)/\(stream)")
            }
        }

        // Past the cap, the oldest lines leave both the buffer and the filtered view.
        model.searchText = "failed"
        model.streamFilter = .all
        model.append(ContainerLogsFixtures.lines(from: &next, count: model.maxLogEntries))
        XCTAssertEqual(model.logEntries.count, model.maxLogEntries)
        assertMatchesRescan(model, "after trimming to the cap")
        model.append(ContainerLogsFixtures.lines(from: &next, count: 10))
        assertMatchesRescan(model, "after a batch at the cap")

        model.clearLogs()
        XCTAssertEqual(model.filteredEntries.count, 0)
        model.append(ContainerLogsFixtures.lines(from: &next, count: 50))
        assertMatchesRescan(model, "after clearing and appending")

        // Replacing the buffer outright: newer lines, older lines prepended, older
        // lines alone, and a replacement that keeps both ends but drops a matching
        // line in between — the case endpoint ids alone would miss.
        let older = Self.entries(from: 0, count: 40)
        let newer = Self.entries(from: 40, count: 40)
        model.logEntries = newer
        assertMatchesRescan(model, "after replacing the buffer")
        model.logEntries = older + newer
        assertMatchesRescan(model, "after prepending older lines")
        model.logEntries = older
        assertMatchesRescan(model, "after replacing the buffer with older lines")
        model.logEntries = older + newer
        var gapped = model.logEntries
        let droppedMatch = try XCTUnwrap(
            gapped.indices.dropFirst().dropLast().first { gapped[$0].message.contains("failed") })
        gapped.remove(at: droppedMatch)
        model.logEntries = gapped
        assertMatchesRescan(model, "after removing a matching line from the middle")
        XCTAssertFalse(model.filteredEntries.contains { $0.id == (older + newer)[droppedMatch].id })

        model.searchText = ""
        XCTAssertEqual(model.filteredEntries.map(\.id), model.logEntries.map(\.id))
    }

    func testSearchIsCaseInsensitiveAndAppliesWithTheStreamFilter() {
        let model = ContainerLogsModel()
        model.logEntries = [
            LogEntry(timestamp: nil, stream: .stdout, message: "Listening on :8080"),
            LogEntry(timestamp: nil, stream: .stderr, message: "listening socket closed"),
            LogEntry(timestamp: nil, stream: .stderr, message: "panic: nil map"),
        ]
        model.searchText = "LISTEN"
        XCTAssertEqual(model.filteredEntries.map(\.message), ["Listening on :8080", "listening socket closed"])
        model.streamFilter = .stderr
        XCTAssertEqual(model.filteredEntries.map(\.message), ["listening socket closed"])
        model.searchText = ""
        XCTAssertEqual(model.filteredEntries.map(\.message), ["listening socket closed", "panic: nil map"])
    }

    // MARK: - Oracle

    /// The filter as the tab computed it before the cache: a full pass over the buffer.
    private func assertMatchesRescan(_ model: ContainerLogsModel, _ context: String, line: UInt = #line) {
        var expected = model.logEntries
        switch model.streamFilter {
        case .all: break
        case .stdout: expected = expected.filter { $0.stream == .stdout }
        case .stderr: expected = expected.filter { $0.stream == .stderr }
        }
        if !model.searchText.isEmpty {
            expected = expected.filter { $0.message.localizedCaseInsensitiveContains(model.searchText) }
        }
        XCTAssertEqual(model.filteredEntries.map(\.id), expected.map(\.id), context, line: line)
        XCTAssertEqual(model.filteredEntries.map(\.message), expected.map(\.message), context, line: line)
    }

    private static let filters: [(String, LogStreamFilter)] = [
        ("failed", .all), ("failed", .stderr), ("", .stdout), ("REQUEST 1", .all), ("served in", .stderr), ("", .all),
    ]

    private static func entries(from start: Int, count: Int) -> [LogEntry] {
        (start..<start + count).map { index in
            LogEntry(timestamp: nil, stream: index % 2 == 0 ? .stdout : .stderr, message: "line \(index) failed")
        }
    }
}
