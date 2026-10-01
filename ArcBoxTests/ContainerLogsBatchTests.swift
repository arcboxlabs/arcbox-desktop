import AppKit
import DockerClient
import SwiftUI
import XCTest

@testable import ArcBox

/// Pins the per-batch cost of the logs tab to the batch, not the buffer.
///
/// A followed container appends a batch of lines every `appendInterval`. Each
/// batch must pay for the new rows and the visible ones, whatever the buffer
/// holds: the tests seed buffers of 600, 3,000 and 6,000 lines, append 200
/// batches of 10 through the production path and compare the per-batch cost.
@MainActor
final class ContainerLogsBatchTests: XCTestCase {
    private static let batches = 200
    private static let batchSize = 10
    /// A detail pane's size; the viewport then shows about 35 rows.
    private static let contentSize = NSSize(width: 960, height: 640)

    func testBatchCostIsFlatAcrossBufferSizes() throws {
        let runs = try [600, 3_000, 6_000].map { try runBatches(seeded: $0) }
        for run in runs { print(run.summary) }
        let small = runs[0]
        let large = runs[2]

        for run in runs {
            XCTAssertLessThanOrEqual(
                run.rowsPerBatch.max() ?? 0, run.visibleRows + Self.batchSize,
                "\(run.label): a batch evaluated more rows than are visible plus the batch"
            )
        }
        XCTAssertLessThanOrEqual(
            large.median / small.median, 1.5,
            "median per batch at \(large.seeded) lines is \(large.median) vs \(small.median) at \(small.seeded)"
        )
    }

    func testFilteredBatchCostIsFlatAcrossBufferSizes() throws {
        for (label, search, stream) in [("search", "failed", LogStreamFilter.all), ("stderr", "", .stderr)] {
            let small = try runBatches(seeded: 600, search: search, stream: stream)
            let large = try runBatches(seeded: 6_000, search: search, stream: stream)
            print(small.summary)
            print(large.summary)
            XCTAssertLessThanOrEqual(
                large.rowsPerBatch.max() ?? 0, large.visibleRows + Self.batchSize,
                "\(label): a batch evaluated more rows than are visible plus the batch"
            )
            XCTAssertLessThanOrEqual(
                large.median / small.median, 1.5,
                "\(label): median per batch at 6,000 lines is \(large.median) vs \(small.median) at 600"
            )
        }
    }

    // MARK: - Harness

    private struct BatchRun {
        let label: String
        let seeded: Int
        let visibleRows: Int
        let perBatch: [Duration]
        let rowsPerBatch: [Int]

        var median: Duration { percentile(50) }
        var p90: Duration { percentile(90) }

        func percentile(_ percent: Int) -> Duration {
            let sorted = perBatch.sorted()
            return sorted[(sorted.count - 1) * percent / 100]
        }

        var summary: String {
            let rows = rowsPerBatch.sorted()
            return "ContainerLogsBatchTests: \(label) seeded=\(seeded) visibleRows=\(visibleRows) "
                + "median=\(median) p90=\(p90) rows/batch median=\(rows[rows.count / 2]) max=\(rows.last ?? 0)"
        }
    }

    /// Hosts the tab, seeds `seeded` lines, then appends `batches` batches and
    /// times each one with its layout pass.
    private func runBatches(seeded: Int, search: String = "", stream: LogStreamFilter = .all) throws -> BatchRun {
        let model = ContainerLogsModel()
        let host = OffscreenHost(
            ContainerLogsTab(container: ContainerLogsFixtures.container, model: model), contentSize: Self.contentSize)
        defer { host.close() }
        // `startStreaming` has run by now (no Docker client, so it only reset
        // the model); seed the buffer through the production path.
        model.errorMessage = nil
        model.searchText = search
        model.streamFilter = stream
        var next = 0
        model.append(ContainerLogsFixtures.lines(from: &next, count: seeded))
        host.settle()

        let scrollView = try XCTUnwrap(host.scrollViews().first)
        let rowHeight = scrollView.documentHeight / Double(model.filteredEntries.count)
        let visibleRows = Int((scrollView.documentVisibleRect.height / rowHeight).rounded(.up)) + 1

        BodyEvaluationCounter.reset()
        let clock = ContinuousClock()
        var perBatch: [Duration] = []
        var rowsPerBatch: [Int] = []
        for _ in 0..<Self.batches {
            let lines = ContainerLogsFixtures.lines(from: &next, count: Self.batchSize)
            let rowsBefore = BodyEvaluationCounter.count(of: ContainerLogsRow.self)
            perBatch.append(
                clock.measure {
                    model.append(lines)
                    host.pump()
                })
            rowsPerBatch.append(BodyEvaluationCounter.count(of: ContainerLogsRow.self) - rowsBefore)
        }
        let filters = [search.isEmpty ? nil : "search=\(search)", stream == .all ? nil : "stream=\(stream)"]
        return BatchRun(
            label: filters.compactMap { $0 }.joined(separator: " ").isEmpty
                ? "unfiltered" : filters.compactMap { $0 }.joined(separator: " "),
            seeded: seeded,
            visibleRows: visibleRows,
            perBatch: perBatch,
            rowsPerBatch: rowsPerBatch
        )
    }
}
