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
    /// `ContainerLogsModel.maxLogEntries`: at that size every batch also trims the buffer.
    private static let cap = 10_000
    private static let bufferSizes = [600, 3_000, 6_000, cap]
    /// A detail pane's size; the viewport then shows about 35 rows.
    private static let contentSize = NSSize(width: 960, height: 640)

    func testBatchCostIsFlatAcrossBufferSizes() throws {
        try assertFlat(runs: runBatches(search: "", stream: .all))
    }

    /// The narrow search keeps one line in seven; the stdout filter keeps six, so at
    /// the cap nearly every trimmed line leaves the filtered view too.
    func testFilteredBatchCostIsFlatAcrossBufferSizes() throws {
        for (search, stream) in [("failed", LogStreamFilter.all), ("", .stdout)] {
            try assertFlat(runs: runBatches(search: search, stream: stream))
        }
    }

    /// Each batch evaluates no more rows than are visible plus the batch, and the
    /// median per batch stays within 1.5x of the smallest buffer's. The run at the
    /// cap is held to the largest uncapped buffer instead: it is the one where the
    /// block trim lands, a linear step paid once per `trimBlock` lines.
    private func assertFlat(runs: [BatchRun]) {
        for run in runs { print(run.summary) }
        let uncapped = runs.filter { $0.seeded < Self.cap }
        for run in runs {
            XCTAssertLessThanOrEqual(
                run.rowsPerBatch.max() ?? 0, run.visibleRows + Self.batchSize,
                "\(run.label) at \(run.seeded): a batch evaluated more rows than are visible plus the batch"
            )
            let baseline = run.seeded < Self.cap ? uncapped.first! : uncapped.last!
            XCTAssertLessThanOrEqual(
                run.median / baseline.median, 1.5,
                "\(run.label): median per batch at \(run.seeded) lines is \(run.median) vs \(baseline.median) at \(baseline.seeded)"
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

    /// One hosted tab with `seeded` lines showing, ready to take batches.
    @MainActor
    private final class HostedBuffer {
        let seeded: Int
        let model = ContainerLogsModel()
        let host: OffscreenHost
        let visibleRows: Int
        var next = 0
        var perBatch: [Duration] = []
        var rowsPerBatch: [Int] = []

        init(seeded: Int, search: String, stream: LogStreamFilter) throws {
            self.seeded = seeded
            host = OffscreenHost(
                ContainerLogsTab(container: ContainerLogsFixtures.container, model: model), contentSize: contentSize)
            // `startStreaming` has run by now (no Docker client, so it only reset
            // the model); seed the buffer through the production path.
            model.errorMessage = nil
            model.searchText = search
            model.streamFilter = stream
            model.append(ContainerLogsFixtures.lines(from: &next, count: seeded))
            host.settle()

            let scrollView = try XCTUnwrap(host.scrollViews().first)
            let rowHeight = scrollView.documentHeight / Double(model.filteredEntries.count)
            visibleRows = Int((scrollView.documentVisibleRect.height / rowHeight).rounded(.up)) + 1

            // The first batch after seeding re-lays out the lazy stack's whole realized
            // window (52 rows for a short filtered list): the seed settling, not a batch.
            model.append(ContainerLogsFixtures.lines(from: &next, count: batchSize))
            host.pump()
        }

        /// Appends one batch with its layout pass, recording the time and the rows evaluated.
        func batch() {
            let lines = ContainerLogsFixtures.lines(from: &next, count: batchSize)
            let rowsBefore = BodyEvaluationCounter.count(of: ContainerLogsRow.self)
            perBatch.append(
                ContinuousClock().measure {
                    model.append(lines)
                    host.pump()
                })
            rowsPerBatch.append(BodyEvaluationCounter.count(of: ContainerLogsRow.self) - rowsBefore)
        }
    }

    /// Hosts a tab per buffer size, one after another, and appends `batches` batches
    /// to each.
    private func runBatches(search: String, stream: LogStreamFilter) throws -> [BatchRun] {
        let filters = [search.isEmpty ? nil : "search=\(search)", stream == .all ? nil : "stream=\(stream)"]
        let label = filters.compactMap { $0 }.joined(separator: " ")
        return try Self.bufferSizes.map { seeded in
            let buffer = try HostedBuffer(seeded: seeded, search: search, stream: stream)
            defer { buffer.host.close() }
            BodyEvaluationCounter.reset()
            for _ in 0..<Self.batches { buffer.batch() }
            return BatchRun(
                label: label.isEmpty ? "unfiltered" : label,
                seeded: seeded,
                visibleRows: buffer.visibleRows,
                perBatch: buffer.perBatch,
                rowsPerBatch: buffer.rowsPerBatch
            )
        }
    }
}
