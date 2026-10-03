import ArcBoxClient
import Foundation

/// Drives the Activity Monitor: subscribes to the daemon's `StatsService`
/// stream, derives rates from the cumulative counters, and keeps a short
/// rolling history for the sparklines.
///
/// Subscribing is passive observation — the daemon never treats a stats
/// watch as VM activity, so leaving this view open does not hold the VM
/// out of idle reclaim.
@MainActor
@Observable
final class ActivityViewModel {
    /// Lifecycle of the stats stream, explicit so the UI can distinguish
    /// "no sample yet" from "had samples, connection dropped, retrying".
    /// There is no terminal failure: the run loop retries until the view
    /// disappears, so persistent errors surface as a climbing `attempt`.
    enum StreamPhase: Equatable {
        /// Connecting; nothing received on this connection yet.
        case connecting
        /// Samples are flowing.
        case live
        /// The stream ended or errored; retrying (attempt count for the UI).
        case reconnecting(attempt: Int)
    }

    /// Latest computed machine stats, or `nil` before the first delta.
    private(set) var current: MachineResourceStats?
    /// Current stream lifecycle phase.
    private(set) var phase: StreamPhase = .connecting
    /// Whether a sample arrived on the current stream connection.
    var isLive: Bool { phase == .live }

    /// Rolling per-metric history (oldest first) for the charts.
    private(set) var cpuHistory: [MetricPoint] = []
    private(set) var memoryHistory: [MetricPoint] = []
    private(set) var networkHistory: [MetricPoint] = []

    /// One charted sample. `index` is a monotonic sequence number so
    /// Swift Charts has a stable, gap-free x-axis.
    struct MetricPoint: Identifiable {
        let index: Int
        let value: Double
        /// Guest monotonic clock at the sample. The x-axis counts samples, not
        /// time, so this is what lets a scrubbed point report how long ago it
        /// was rather than assuming the stream ticks at exactly 1 Hz.
        let monotonicMs: UInt64
        var id: Int { index }
    }

    private var previousSample: Arcbox_V1_MachineStats?
    private var sequence = 0
    private static let historyLength = 60  // ~1 min at 1 Hz

    /// Streams stats with reconnect until the calling task is cancelled
    /// (driven by SwiftUI `.task`, which cancels on view disappearance).
    /// Mirrors the reconnect loop in `DaemonManager+Watch`; the gRPC detail
    /// lives in `ArcBoxClient.machineStatsStream()`.
    func run(client: ArcBoxClient) async {
        previousSample = nil
        phase = .connecting
        defer { phase = .connecting }

        var attempt = 0
        while !Task.isCancelled {
            // A fresh stream each iteration re-reads the client's transport,
            // which it swaps on recovery.
            for await sample in client.machineStatsStream() {
                guard !Task.isCancelled else { break }
                ingest(sample)
                attempt = 0
            }
            guard !Task.isCancelled else { return }
            attempt += 1
            phase = .reconnecting(attempt: attempt)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Folds one raw sample into `current` and the histories. Internal rather
    /// than private so a test can drive the exact per-tick path without a
    /// daemon stream behind it.
    func ingest(_ sample: Arcbox_V1_MachineStats) {
        defer { previousSample = sample }
        guard let previous = previousSample,
            let computed = ResourceStatsCalculator.compute(previous: previous, current: sample)
        else {
            // First sample or a counter reset (guest reboot): rebaseline.
            return
        }
        current = computed
        phase = .live
        sequence += 1
        append(&cpuHistory, computed.cpuPercent, at: sample.monotonicMs)
        append(&memoryHistory, computed.memoryUsedPercent, at: sample.monotonicMs)
        append(
            &networkHistory,
            computed.networkReceiveBytesPerSecond + computed.networkTransmitBytesPerSecond,
            at: sample.monotonicMs)
    }

    private func append(_ series: inout [MetricPoint], _ value: Double, at monotonicMs: UInt64) {
        series.append(MetricPoint(index: sequence, value: value, monotonicMs: monotonicMs))
        if series.count > Self.historyLength {
            series.removeFirst(series.count - Self.historyLength)
        }
    }
}
