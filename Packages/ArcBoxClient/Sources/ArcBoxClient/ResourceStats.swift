import Foundation

/// Machine-level resource rates and gauges derived from two consecutive
/// `Arcbox_V1_MachineStats` samples.
///
/// The daemon streams cumulative counters (see `stats.proto`); rates are
/// derived here from deltas over the guest monotonic clock, mirroring
/// `abctl top` so the desktop and CLI agree. This keeps the view layer
/// free of counter arithmetic.
public struct MachineResourceStats: Sendable, Equatable {
    public var cpuPercent: Double
    public var onlineCPUs: UInt32
    public var loadaverage1: Double
    public var memoryTotalBytes: UInt64
    public var memoryUsedBytes: UInt64
    public var memoryUsedPercent: Double
    /// PSI memory `full avg10` (0–100). Negative when the guest kernel
    /// lacks `CONFIG_PSI`; the view shows "n/a" in that case.
    public var memoryPressurePercent: Double
    public var diskReadBytesPerSecond: Double
    public var diskWriteBytesPerSecond: Double
    public var networkReceiveBytesPerSecond: Double
    public var networkTransmitBytesPerSecond: Double
    public var containers: [ContainerResourceStats]

    /// Whether the guest kernel reported a usable PSI pressure gauge.
    public var hasMemoryPressure: Bool { memoryPressurePercent >= 0 }
}

/// One container's resource rates and gauges, derived from the same two
/// samples. `Identifiable` by container ID for use in SwiftUI lists.
public struct ContainerResourceStats: Sendable, Equatable, Identifiable {
    public var id: String
    /// Daemon-enriched name, or the 12-char short ID when unknown.
    public var displayName: String
    /// Percent of one core (may exceed 100 for a multi-threaded
    /// container), matching `docker stats`.
    public var cpuPercent: Double
    public var memoryCurrentBytes: UInt64
    /// 0 means unlimited.
    public var memoryLimitBytes: UInt64
    public var diskReadBytesPerSecond: Double
    public var diskWriteBytesPerSecond: Double
    public var pids: UInt32
}

/// Derives `MachineResourceStats` from consecutive raw samples.
public enum ResourceStatsCalculator {
    /// Computes rates between two samples.
    ///
    /// Returns `nil` when the guest clock or CPU counters went backwards —
    /// the counters reset (guest reboot) and the caller should treat
    /// `current` as the new baseline instead of emitting nonsense rates.
    public static func compute(
        previous: Arcbox_V1_MachineStats,
        current: Arcbox_V1_MachineStats
    ) -> MachineResourceStats? {
        guard current.monotonicMs > previous.monotonicMs,
            current.cpuTotalTicks > previous.cpuTotalTicks
        else {
            return nil
        }
        let dt = Double(current.monotonicMs - previous.monotonicMs) / 1000.0
        let totalTicks = Double(current.cpuTotalTicks - previous.cpuTotalTicks)
        let busyTicks = Double(current.cpuBusyTicks.subtractingReportingOverflow(previous.cpuBusyTicks).0)

        let memoryUsed = current.memoryTotalBytes >= current.memoryAvailableBytes
            ? current.memoryTotalBytes - current.memoryAvailableBytes
            : 0

        return MachineResourceStats(
            cpuPercent: min(busyTicks / totalTicks * 100, 100),
            onlineCPUs: current.onlineCpus,
            loadaverage1: current.loadavg1,
            memoryTotalBytes: current.memoryTotalBytes,
            memoryUsedBytes: memoryUsed,
            memoryUsedPercent: current.memoryTotalBytes == 0
                ? 0
                : Double(memoryUsed) / Double(current.memoryTotalBytes) * 100,
            memoryPressurePercent: current.memoryPsiFullAvg10,
            diskReadBytesPerSecond: rate(current.diskReadBytes, previous.diskReadBytes, dt),
            diskWriteBytesPerSecond: rate(current.diskWrittenBytes, previous.diskWrittenBytes, dt),
            networkReceiveBytesPerSecond: rate(current.netRxBytes, previous.netRxBytes, dt),
            networkTransmitBytesPerSecond: rate(current.netTxBytes, previous.netTxBytes, dt),
            containers: computeContainers(previous: previous, current: current, dt: dt)
        )
    }

    /// Joins each current container with its previous sample by ID,
    /// computes per-container rates, and sorts by CPU descending. A
    /// container with no prior sample (just started) reports 0% CPU until
    /// the next frame gives it a baseline.
    private static func computeContainers(
        previous: Arcbox_V1_MachineStats,
        current: Arcbox_V1_MachineStats,
        dt: Double
    ) -> [ContainerResourceStats] {
        let priors = Dictionary(
            previous.containers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let computed = current.containers.map { container -> ContainerResourceStats in
            let prior = priors[container.id]
            let cpuPercent: Double
            if let prior, container.cpuUsageUsec > prior.cpuUsageUsec {
                cpuPercent = Double(container.cpuUsageUsec - prior.cpuUsageUsec)
                    / (dt * 1_000_000) * 100
            } else {
                cpuPercent = 0
            }
            return ContainerResourceStats(
                id: container.id,
                displayName: container.name.isEmpty
                    ? String(container.id.prefix(12))
                    : container.name,
                cpuPercent: cpuPercent,
                memoryCurrentBytes: container.memoryCurrentBytes,
                memoryLimitBytes: container.memoryLimitBytes,
                diskReadBytesPerSecond: rate(
                    container.diskReadBytes, prior?.diskReadBytes ?? container.diskReadBytes, dt),
                diskWriteBytesPerSecond: rate(
                    container.diskWrittenBytes, prior?.diskWrittenBytes ?? container.diskWrittenBytes, dt),
                pids: container.pids
            )
        }
        return computed.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private static func rate(_ current: UInt64, _ previous: UInt64, _ dt: Double) -> Double {
        guard current >= previous, dt > 0 else { return 0 }
        return Double(current - previous) / dt
    }
}
