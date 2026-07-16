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
    /// Latest computed machine stats, or `nil` before the first delta.
    private(set) var current: MachineResourceStats?
    /// Whether a sample arrived on the current stream connection.
    private(set) var isLive = false

    /// Rolling per-metric history (oldest first) for the charts.
    private(set) var cpuHistory: [MetricPoint] = []
    private(set) var memoryHistory: [MetricPoint] = []
    private(set) var networkHistory: [MetricPoint] = []

    /// One charted sample. `index` is a monotonic sequence number so
    /// Swift Charts has a stable, gap-free x-axis.
    struct MetricPoint: Identifiable {
        let index: Int
        let value: Double
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
        defer { isLive = false }

        while !Task.isCancelled {
            // A fresh stream each iteration re-reads the client's transport,
            // which it swaps on recovery.
            for await sample in client.machineStatsStream() {
                guard !Task.isCancelled else { break }
                ingest(sample)
            }
            isLive = false
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func ingest(_ sample: Arcbox_V1_MachineStats) {
        defer { previousSample = sample }
        guard let previous = previousSample,
            let computed = ResourceStatsCalculator.compute(previous: previous, current: sample)
        else {
            // First sample or a counter reset (guest reboot): rebaseline.
            return
        }
        current = computed
        isLive = true
        sequence += 1
        append(&cpuHistory, computed.cpuPercent)
        append(&memoryHistory, computed.memoryUsedPercent)
        append(
            &networkHistory,
            computed.networkReceiveBytesPerSecond + computed.networkTransmitBytesPerSecond)
    }

    private func append(_ series: inout [MetricPoint], _ value: Double) {
        series.append(MetricPoint(index: sequence, value: value))
        if series.count > Self.historyLength {
            series.removeFirst(series.count - Self.historyLength)
        }
    }
}
