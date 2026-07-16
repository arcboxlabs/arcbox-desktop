import Testing

@testable import ArcBoxClient

@Suite struct ResourceStatsTests {
    private func machine(monotonicMs: UInt64, busy: UInt64, total: UInt64) -> Arcbox_V1_MachineStats {
        var m = Arcbox_V1_MachineStats()
        m.monotonicMs = monotonicMs
        m.cpuBusyTicks = busy
        m.cpuTotalTicks = total
        m.onlineCpus = 4
        m.loadavg1 = 0.5
        m.memoryTotalBytes = 8 * 1024 * 1024 * 1024
        m.memoryAvailableBytes = 6 * 1024 * 1024 * 1024
        m.memoryPsiFullAvg10 = 0.5
        m.diskReadBytes = 1000
        m.diskWrittenBytes = 2000
        m.netRxBytes = 3000
        m.netTxBytes = 4000
        return m
    }

    private func container(_ id: String, cpuUsec: UInt64, memory: UInt64, name: String = "")
        -> Arcbox_V1_ContainerStats
    {
        var c = Arcbox_V1_ContainerStats()
        c.id = id
        c.name = name
        c.cpuUsageUsec = cpuUsec
        c.memoryCurrentBytes = memory
        c.pids = 3
        return c
    }

    @Test func ratesComeFromDeltasOverGuestTime() {
        let prev = machine(monotonicMs: 10_000, busy: 100, total: 1000)
        var cur = machine(monotonicMs: 12_000, busy: 150, total: 1200)  // +2s, 50/200 busy
        cur.diskReadBytes = 1000 + 2048
        cur.netTxBytes = 4000 + 1024

        let stats = ResourceStatsCalculator.compute(previous: prev, current: cur)
        #expect(stats != nil)
        #expect(abs(stats!.cpuPercent - 25.0) < 0.001)
        #expect(abs(stats!.diskReadBytesPerSecond - 1024.0) < 0.001)
        #expect(abs(stats!.networkTransmitBytesPerSecond - 512.0) < 0.001)
        #expect(abs(stats!.memoryUsedPercent - 25.0) < 0.01)
    }

    @Test func counterResetAsksForNewBaseline() {
        // Guest rebooted: monotonic clock and ticks both went backwards.
        let prev = machine(monotonicMs: 500_000, busy: 4000, total: 50_000)
        let cur = machine(monotonicMs: 3_000, busy: 10, total: 100)
        #expect(ResourceStatsCalculator.compute(previous: prev, current: cur) == nil)
    }

    @Test func containerCpuFromUsecDeltaAndSortedDescending() {
        var prev = machine(monotonicMs: 10_000, busy: 100, total: 1000)
        var cur = machine(monotonicMs: 12_000, busy: 150, total: 1200)  // +2s
        prev.containers = [container("busy", cpuUsec: 0, memory: 100), container("idle", cpuUsec: 0, memory: 50)]
        cur.containers = [
            container("idle", cpuUsec: 0, memory: 50),  // no CPU movement
            container("busy", cpuUsec: 1_000_000, memory: 100),  // +1s cpu over 2s = 50%
        ]

        let stats = ResourceStatsCalculator.compute(previous: prev, current: cur)!
        #expect(stats.containers[0].id == "busy")
        #expect(abs(stats.containers[0].cpuPercent - 50.0) < 0.01)
        #expect(stats.containers[1].cpuPercent == 0)
    }

    @Test func freshContainerReportsZeroCpuUntilBaseline() {
        let prev = machine(monotonicMs: 10_000, busy: 100, total: 1000)
        var cur = machine(monotonicMs: 12_000, busy: 150, total: 1200)
        cur.containers = [container("fresh", cpuUsec: 5_000_000, memory: 128)]

        let stats = ResourceStatsCalculator.compute(previous: prev, current: cur)!
        #expect(stats.containers.count == 1)
        #expect(stats.containers[0].cpuPercent == 0)  // no baseline → 0, not a spike
    }

    @Test func emptyNameFallsBackToShortID() {
        let id = "0a1b2c3d4e5f00112233445566778899aabbccddeeff00112233445566778899"
        let prev = machine(monotonicMs: 10_000, busy: 100, total: 1000)
        var cur = machine(monotonicMs: 12_000, busy: 150, total: 1200)
        cur.containers = [container(id, cpuUsec: 0, memory: 64)]

        let stats = ResourceStatsCalculator.compute(previous: prev, current: cur)!
        #expect(stats.containers[0].displayName == "0a1b2c3d4e5f")
    }

    @Test func enrichedNameIsPreferred() {
        let prev = machine(monotonicMs: 10_000, busy: 100, total: 1000)
        var cur = machine(monotonicMs: 12_000, busy: 150, total: 1200)
        cur.containers = [container("abcdef123456", cpuUsec: 0, memory: 64, name: "arcbox-postgres-1")]

        let stats = ResourceStatsCalculator.compute(previous: prev, current: cur)!
        #expect(stats.containers[0].displayName == "arcbox-postgres-1")
    }

    @Test func containerNetworkRateFromDeltas() {
        var prev = machine(monotonicMs: 10_000, busy: 100, total: 1000)
        var cur = machine(monotonicMs: 12_000, busy: 150, total: 1200)  // +2s
        var p = container("net", cpuUsec: 0, memory: 100)
        p.netRxBytes = 1000
        p.netTxBytes = 2000
        prev.containers = [p]
        var n = container("net", cpuUsec: 0, memory: 100)
        n.netRxBytes = 1000 + 4096  // +2 KiB/s
        n.netTxBytes = 2000 + 1024  // +512 B/s
        cur.containers = [n]

        let stats = ResourceStatsCalculator.compute(previous: prev, current: cur)!
        #expect(abs(stats.containers[0].networkReceiveBytesPerSecond - 2048.0) < 0.001)
        #expect(abs(stats.containers[0].networkTransmitBytesPerSecond - 512.0) < 0.001)
    }

    @Test func negativePsiMeansNoPressureGauge() {
        let prev = machine(monotonicMs: 10_000, busy: 100, total: 1000)
        var cur = machine(monotonicMs: 12_000, busy: 150, total: 1200)
        cur.memoryPsiFullAvg10 = -1

        let stats = ResourceStatsCalculator.compute(previous: prev, current: cur)!
        #expect(stats.hasMemoryPressure == false)
    }
}
