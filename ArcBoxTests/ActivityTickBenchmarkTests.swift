import AppKit
import ArcBoxClient
import SwiftUI
import XCTest

@testable import ArcBox

/// Main-thread cost of one stats sample landing on the Activity screen.
///
/// The daemon streams a sample a second, and every sample re-evaluates the
/// metric strip and the container table (Sentry ARCBOX-DESKTOP-SWIFT-3G, -B5,
/// -B6 are App Hangs sampled inside exactly that update). This hosts the views
/// the way `ActivityView.content` composes them, folds samples through
/// `ActivityViewModel.ingest` — the same path the stream drives — and measures
/// the wall time each one costs the main thread.
///
/// The budgets are on the median, not the maximum, and sit at several times
/// the median measured on an M-series host in a Debug build (2026-10-01, see
/// the PR), so a slower CI runner does not fail them on noise.
///
/// `ARCBOX_ACTIVITY_BENCH_TICKS` lengthens the loop so `sample(1)` can
/// attribute the cost; the default is short enough for CI.
/// `ARCBOX_ACTIVITY_BENCH_SHUFFLE=1` randomises every container's CPU each
/// tick so the table re-sorts all of its rows every second — the worst case
/// for the `Table` diff, not the shape of real data.
@MainActor
final class ActivityTickBenchmarkTests: XCTestCase {
    private static let containerCount = 20
    private static let seededSamples = 60
    /// At least one: a median needs a sample.
    private static let ticks = max(
        1, ProcessInfo.processInfo.environment["ARCBOX_ACTIVITY_BENCH_TICKS"].flatMap(Int.init) ?? 60)
    private static let shuffles = ProcessInfo.processInfo.environment["ARCBOX_ACTIVITY_BENCH_SHUFFLE"] == "1"

    /// The three sparklines alone — the headline figures held still so only
    /// the histories move. Measured at 0.56 ms with Canvas; the Swift Charts
    /// figures it replaced took 5.26 ms, so this is the gate that would catch
    /// them coming back.
    func testSparklineTickStaysWithinBudget() throws {
        let tick = try measureTick(of: .sparklines)
        XCTAssertLessThan(tick.median, .milliseconds(2), "a history sample costs the sparklines \(tick)")
    }

    /// The strip: four tiles with live headlines. Most of it is text —
    /// re-rasterizing the glyphs of every tile's display list and compositing
    /// the `numericText` transition — not the figures: 3.5 ms measured, 1.6 ms
    /// with the transition removed (and the animation tail 160 ms → 13 ms).
    func testStripTickStaysWithinBudget() throws {
        let tick = try measureTick(of: .strip)
        XCTAssertLessThan(tick.median, .milliseconds(12), "the strip costs \(tick) per sample")
    }

    /// The whole screen with twenty containers. The table is the bulk of it:
    /// SwiftUI's `Table` reloads every row whose cells changed and re-measures
    /// their heights, about 0.3 ms per changed row: 7–10 ms measured here,
    /// 16.7 ms with the Swift Charts strip, 25 ms when every row re-sorts.
    func testActivityTickStaysWithinBudget() throws {
        let tick = try measureTick(of: .screen)
        XCTAssertLessThan(tick.median, .milliseconds(30), "one sample costs the screen \(tick)")
    }

    private func measureTick(of part: ActivityBenchmarkHost.Part) throws -> TickTiming {
        let vm = ActivityViewModel()
        var feed = SyntheticStatsFeed(containerCount: Self.containerCount, shuffles: Self.shuffles)
        // The first sample only baselines the counters; rates need two.
        for _ in 0...Self.seededSamples {
            vm.ingest(feed.next())
        }
        XCTAssertEqual(vm.cpuHistory.count, Self.seededSamples)
        XCTAssertEqual(vm.current?.containers.count, Self.containerCount)

        let hosting = NSHostingView(
            rootView: ActivityBenchmarkHost(vm: vm, docker: feed.facts, part: part, frozenStats: vm.current)
                .environment(AppViewModel())
                .environment(ContainersViewModel())
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        settle(hosting)

        let clock = ContinuousClock()
        // Flushing with nothing changed prices the harness itself, so the tick
        // numbers can be read net of it.
        let idle = (0..<10).map { _ in clock.measure { flush(hosting) } }

        var ticks: [Duration] = []
        ticks.reserveCapacity(Self.ticks)
        for _ in 0..<Self.ticks {
            let sample = feed.next()
            ticks.append(
                clock.measure {
                    vm.ingest(sample)
                    flush(hosting)
                })
        }

        // A tick also starts animations — the headline's `numericText`
        // transition, the gauge — that keep the main thread drawing for the
        // next 0.3 s. Price that tail in main-thread CPU time, since the ticks
        // above only see the frame the sample lands in.
        var tails: [Duration] = []
        for _ in 0..<5 {
            vm.ingest(feed.next())
            flush(hosting)
            let before = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            tails.append(.nanoseconds(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - before))
        }

        let timing = TickTiming(ticks: ticks, idle: idle, tails: tails)
        print(
            "[activity-bench] part=\(part) rows=\(Self.containerCount) ticks=\(Self.ticks) "
                + "shuffle=\(Self.shuffles) \(timing)")
        return timing
    }

    /// Runs the hosting view through the layout and display passes a sample
    /// change schedules, then commits the layer tree — the main-thread work
    /// between a mutation and the frame it lands in.
    private func flush(_ view: NSView) {
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        CATransaction.flush()
    }

    /// The first frame builds the table's row views and the figures' layers;
    /// that one-off is not a tick.
    private func settle(_ view: NSView) {
        for _ in 0..<5 {
            flush(view)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }
}

private struct TickTiming: CustomStringConvertible {
    let median: Duration
    let p90: Duration
    let max: Duration
    let idleFlush: Duration
    /// Main-thread CPU spent in the 0.4 s after a tick, median of a few.
    let animationTail: Duration

    init(ticks: [Duration], idle: [Duration], tails: [Duration]) {
        median = Self.percentile(ticks, 0.5)
        p90 = Self.percentile(ticks, 0.9)
        max = Self.percentile(ticks, 1)
        idleFlush = Self.percentile(idle, 0.5)
        animationTail = Self.percentile(tails, 0.5)
    }

    /// Nearest-rank percentile; zero for no samples rather than a trap.
    private static func percentile(_ durations: [Duration], _ fraction: Double) -> Duration {
        let sorted = durations.sorted()
        guard !sorted.isEmpty else { return .zero }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
    }

    var description: String {
        "idle-flush=\(Self.format(idleFlush)) median=\(Self.format(median)) "
            + "p90=\(Self.format(p90)) max=\(Self.format(max)) tail-cpu=\(Self.format(animationTail))"
    }

    private static func format(_ duration: Duration) -> String {
        let milliseconds =
            Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.3fms", milliseconds)
    }
}

// MARK: - Host

/// `ActivityView.content` without the daemon: the table under the floating
/// strip, both fed from the view model the way the screen feeds them — or
/// less of it, to price a part by itself.
private struct ActivityBenchmarkHost: View {
    enum Part {
        /// The strip with its headline figures frozen at the seeded sample, so
        /// a tick changes only the three histories.
        case sparklines
        /// The strip alone, live.
        case strip
        /// Strip and table, as the screen composes them.
        case screen
    }

    let vm: ActivityViewModel
    let docker: [String: ActivityContainerFacts]
    let part: Part
    let frozenStats: MachineResourceStats?

    var body: some View {
        switch part {
        case .sparklines, .strip:
            Color.clear.safeAreaInset(edge: .top, spacing: 0) { strip }
        case .screen:
            ActivityContainerTable(
                containers: vm.current?.containers ?? [],
                docker: docker,
                searchText: "",
                hasLoaded: vm.current != nil
            )
            .safeAreaInset(edge: .top, spacing: 0) { strip }
            .softScrollEdge(for: .top)
        }
    }

    private var strip: some View {
        ActivityMetricStrip(
            stats: part == .sparklines ? frozenStats : vm.current,
            cpuHistory: vm.cpuHistory,
            memoryHistory: vm.memoryHistory,
            networkHistory: vm.networkHistory
        )
        .redacted(reason: vm.current == nil ? .placeholder : [])
    }
}

// MARK: - Feed

/// Deterministic raw samples with the shape of a busy machine: every counter
/// moves every second, so each tick reformats every cell and reshapes every
/// sparkline, the way real data does.
///
/// Container load follows the profile a real host shows — a few busy
/// services with counters that move every second, and a long tail of idle
/// ones whose memory holds still, whose disk and network sit at zero and whose
/// CPU only jitters below a percent. `shuffles` replaces that with a fresh
/// random load per container per tick, so the busiest-first sort moves every
/// row.
private struct SyntheticStatsFeed {
    private static let onlineCPUs: UInt32 = 8
    private static let memoryTotal: UInt64 = 16 << 30
    /// Percent of one core per container, busiest first.
    private static let loadProfile: [Double] = [
        45, 30, 22, 15, 12, 9, 7, 5, 4, 3, 2.5, 2, 1.5, 1.2, 1, 0.8, 0.6, 0.4, 0.2, 0.1,
    ]

    private let shuffles: Bool
    private var generator = SplitMix64(seed: 0x5EED_AC71)
    private var monotonicMs: UInt64 = 1_000
    private var cpuBusyTicks: UInt64 = 0
    private var cpuTotalTicks: UInt64 = 0
    private var cpuLevel = 0.35
    private var memoryLevel = 0.55
    private var diskRead: UInt64 = 0
    private var diskWritten: UInt64 = 0
    private var netRx: UInt64 = 0
    private var netTx: UInt64 = 0
    private var containers: [Arcbox_V1_ContainerStats]

    /// Three Compose projects of four containers each; the rest standalone, so
    /// the table exercises both disclosure groups and plain rows.
    let facts: [String: ActivityContainerFacts]

    init(containerCount: Int, shuffles: Bool) {
        self.shuffles = shuffles
        var facts: [String: ActivityContainerFacts] = [:]
        containers = (0..<containerCount).map { ordinal in
            var container = Arcbox_V1_ContainerStats()
            container.id = String(format: "%064x", ordinal + 1)
            container.name = "service-\(ordinal)"
            container.memoryLimitBytes = ordinal.isMultiple(of: 2) ? 2 << 30 : 0
            container.memoryCurrentBytes = (64 << 20) + UInt64(ordinal) << 20
            container.pids = UInt32(4 + ordinal)
            let project = ordinal < 12 ? "project-\(ordinal / 4)" : nil
            facts[container.id] = ActivityContainerFacts(project: project, image: "image-\(ordinal):latest")
            return container
        }
        self.facts = facts
    }

    mutating func next() -> Arcbox_V1_MachineStats {
        monotonicMs += 1_000
        cpuLevel = walk(cpuLevel, step: 0.08)
        memoryLevel = walk(memoryLevel, step: 0.02)
        let totalTicks = UInt64(Self.onlineCPUs) * 100
        cpuTotalTicks += totalTicks
        cpuBusyTicks += UInt64(Double(totalTicks) * cpuLevel)
        diskRead += generator.next(upTo: 50 << 20)
        diskWritten += generator.next(upTo: 20 << 20)
        netRx += generator.next(upTo: 120 << 20)
        netTx += generator.next(upTo: 30 << 20)
        for index in containers.indices {
            containers[index].cpuUsageUsec += containerBusyMicroseconds(at: index)
            guard shuffles || isBusy(index) else { continue }
            containers[index].memoryCurrentBytes = (200 << 20) + generator.next(upTo: 600 << 20)
            containers[index].diskReadBytes += generator.next(upTo: 4 << 20)
            containers[index].diskWrittenBytes += generator.next(upTo: 2 << 20)
            containers[index].netRxBytes += generator.next(upTo: 8 << 20)
            containers[index].netTxBytes += generator.next(upTo: 3 << 20)
        }

        var sample = Arcbox_V1_MachineStats()
        sample.monotonicMs = monotonicMs
        sample.cpuBusyTicks = cpuBusyTicks
        sample.cpuTotalTicks = cpuTotalTicks
        sample.onlineCpus = Self.onlineCPUs
        sample.loadavg1 = Double(generator.next(upTo: 800)) / 100
        sample.memoryTotalBytes = Self.memoryTotal
        sample.memoryAvailableBytes = UInt64(Double(Self.memoryTotal) * (1 - memoryLevel))
        sample.memoryPsiFullAvg10 = Double(generator.next(upTo: 1_200)) / 100
        sample.diskReadBytes = diskRead
        sample.diskWrittenBytes = diskWritten
        sample.netRxBytes = netRx
        sample.netTxBytes = netTx
        sample.containers = containers
        return sample
    }

    /// A container with at least a percent of a core to its name.
    private func isBusy(_ index: Int) -> Bool {
        Self.loadProfile[index % Self.loadProfile.count] >= 1
    }

    /// One second of CPU for a container: its place in the load profile with
    /// ±25% jitter, or a uniformly random load when shuffling.
    private mutating func containerBusyMicroseconds(at index: Int) -> UInt64 {
        if shuffles {
            return generator.next(upTo: 400_000)
        }
        let base = Self.loadProfile[index % Self.loadProfile.count] * 10_000
        let jitter = 0.75 + Double(generator.next(upTo: 1_000)) / 2_000
        return UInt64(base * jitter)
    }

    /// A bounded random walk in 0...1, so the machine's sparklines have a shape
    /// rather than noise.
    private mutating func walk(_ level: Double, step: Double) -> Double {
        let delta = (Double(generator.next(upTo: 1_000)) / 500 - 1) * step
        return min(max(level + delta, 0.02), 0.98)
    }
}

/// SplitMix64: a seedable generator so every run feeds the same samples.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(upTo bound: UInt64) -> UInt64 {
        next() % bound
    }
}
