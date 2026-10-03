import AppKit
import ArcBoxClient
import SwiftUI
import XCTest

@testable import ArcBox

/// Renders the metric strip's tiles over a fixed series so a change to how the
/// sparklines draw can be reviewed by eye. The glass around them is left out:
/// it does not change with the figures, and `cacheDisplay` renders it as its
/// raw normal map. Writes `<prefix>.png` (light) and
/// `<prefix>-dark.png` at 2× into `ARCBOX_ACTIVITY_SNAPSHOT_DIR`, creating it if
/// needed, and is skipped when that is not set: the images are for a reviewer,
/// not a gate.
///
/// Render the tree before and after the change with
/// `ARCBOX_ACTIVITY_SNAPSHOT_PREFIX=before` / `=after` and compare the pairs.
/// `xcodebuild` hands the test process only the variables prefixed
/// `TEST_RUNNER_`, so through the Makefile that is
/// `make test XCODE_ENV="/usr/bin/env -i HOME=$HOME PATH=/usr/bin:/bin
/// TEST_RUNNER_ARCBOX_ACTIVITY_SNAPSHOT_DIR=/tmp/strip
/// TEST_RUNNER_ARCBOX_ACTIVITY_SNAPSHOT_PREFIX=before"
/// XCODEBUILD_EXTRA=-only-testing:ArcBoxTests/ActivityMetricStripSnapshotTests`.
@MainActor
final class ActivityMetricStripSnapshotTests: XCTestCase {
    func testRendersStripInBothAppearancesForReview() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["ARCBOX_ACTIVITY_SNAPSHOT_DIR"] else {
            throw XCTSkip("set ARCBOX_ACTIVITY_SNAPSHOT_DIR to render the strip for review")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let prefix = environment["ARCBOX_ACTIVITY_SNAPSHOT_PREFIX"] ?? "strip"
        let strip = ActivityMetricTiles(
            stats: try XCTUnwrap(Self.stats()),
            cpuHistory: Self.series { tick in 35 + 25 * sin(Double(tick) / 6) + (tick == 41 ? 38 : 0) },
            memoryHistory: Self.series { tick in 40 + Double(tick) * 0.55 },
            networkHistory: Self.series { tick in
                tick.isMultiple(of: 7) ? Double(tick % 5 + 1) * Double(24 << 20) : Double(tick % 3) * 800_000
            }
        )

        for (suffix, appearance) in [("", NSAppearance.Name.aqua), ("-dark", .darkAqua)] {
            let image = try render(strip, appearance: appearance)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(prefix)\(suffix).png")
            let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            try data.write(to: url)
            print("[activity-snapshot] wrote \(url.path) (\(image.pixelsWide)×\(image.pixelsHigh) px)")
        }
    }

    /// The strip at the main window's usual width, drawn by AppKit in a window
    /// of the given appearance — `ImageRenderer` skips the gauge and resolves
    /// system colors on its own terms — into a 2× bitmap regardless of the
    /// host's display, so two renders line up pixel for pixel.
    private func render(_ strip: ActivityMetricTiles, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(
            rootView: strip.padding(20).frame(width: 1_000).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
        window.contentView = hosting
        defer { window.close() }
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }

        let bounds = hosting.bounds
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * 2),
                pixelsHigh: Int(bounds.height * 2),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ))
        bitmap.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }

    // MARK: - Fixtures

    /// One second of a moderately busy machine, derived the way the view model
    /// derives it — the model's initializer is the package's, not ours.
    private static func stats() -> MachineResourceStats? {
        var previous = Arcbox_V1_MachineStats()
        previous.monotonicMs = (5 * 3_600 + 12 * 60) * 1_000
        previous.cpuTotalTicks = 100_000
        previous.cpuBusyTicks = 40_000
        var current = previous
        current.monotonicMs += 1_000
        current.cpuTotalTicks += 800
        current.cpuBusyTicks += 340
        current.onlineCpus = 8
        current.loadavg1 = 3.41
        current.memoryTotalBytes = 16 << 30
        current.memoryAvailableBytes = 5 << 30
        current.memoryPsiFullAvg10 = 6.5
        current.diskReadBytes = 12 << 20
        current.diskWrittenBytes = 3 << 20
        current.netRxBytes = 48 << 20
        current.netTxBytes = 9 << 20
        return ResourceStatsCalculator.compute(previous: previous, current: current)
    }

    private static func series(_ value: (Int) -> Double) -> [ActivityViewModel.MetricPoint] {
        (0..<60).map { tick in
            ActivityViewModel.MetricPoint(
                index: 100 + tick,
                value: max(0, value(tick)),
                monotonicMs: UInt64(1_000 * (100 + tick))
            )
        }
    }
}
