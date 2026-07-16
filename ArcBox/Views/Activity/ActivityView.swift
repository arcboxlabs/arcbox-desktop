import ArcBoxClient
import Charts
import SwiftUI

/// Live resource monitor for the System VM: machine CPU / memory / network
/// with short history sparklines, a PSI memory-pressure gauge, and a
/// per-container table. Backed by the daemon's `StatsService` stream via
/// `ActivityViewModel`.
struct ActivityView: View {
    @Environment(ActivityViewModel.self) private var vm
    @Environment(\.arcboxClient) private var arcboxClient

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let stats = vm.current {
                    charts(stats)
                    containerSection(stats)
                } else {
                    waitingForData
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.background)
        .navigationTitle("Activity")
        // Re-key on the client's identity so the stream (re)starts when the
        // client first becomes available or is swapped.
        .task(id: arcboxClient.map(ObjectIdentifier.init)) {
            guard let client = arcboxClient else { return }
            await vm.run(client: client)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("System VM")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.text)
            Spacer()
            if vm.isLive {
                StatusBadge(color: AppColors.running, label: "LIVE")
            }
        }
    }

    private var waitingForData: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Waiting for the first sample…")
                .foregroundStyle(AppColors.textSecondary)
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Charts

    private func charts(_ stats: MachineResourceStats) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240), spacing: 12)],
            spacing: 12
        ) {
            SparklineCard(
                title: "CPU",
                value: StatsFormat.percent(stats.cpuPercent),
                subtitle: "\(stats.onlineCPUs) cores · load \(String(format: "%.2f", stats.loadaverage1))",
                points: vm.cpuHistory,
                tint: AppColors.running,
                yDomain: 0...100
            )
            SparklineCard(
                title: "Memory",
                value: StatsFormat.percent(stats.memoryUsedPercent),
                subtitle: "\(StatsFormat.bytes(stats.memoryUsedBytes)) / \(StatsFormat.bytes(stats.memoryTotalBytes))",
                points: vm.memoryHistory,
                tint: AppColors.accent,
                yDomain: 0...100
            )
            SparklineCard(
                title: "Network",
                value: StatsFormat.rate(
                    stats.networkReceiveBytesPerSecond + stats.networkTransmitBytesPerSecond),
                subtitle: "↓ \(StatsFormat.rate(stats.networkReceiveBytesPerSecond))   ↑ \(StatsFormat.rate(stats.networkTransmitBytesPerSecond))",
                points: vm.networkHistory,
                tint: AppColors.warning,
                yDomain: nil
            )
            PressureCard(stats: stats)
        }
    }

    // MARK: - Containers

    @ViewBuilder
    private func containerSection(_ stats: MachineResourceStats) -> some View {
        Text("Containers")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.sectionHeader)
            .textCase(.uppercase)
            .padding(.top, 4)

        if stats.containers.isEmpty {
            Text("No running containers")
                .foregroundStyle(AppColors.textMuted)
                .font(.system(size: 13))
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ContainerStatsHeader()
                ForEach(stats.containers) { container in
                    ContainerStatsRow(container: container)
                    if container.id != stats.containers.last?.id {
                        Divider().overlay(AppColors.borderSubtle)
                    }
                }
            }
            .cardStyle()
        }
    }
}

// MARK: - Sparkline card

private struct SparklineCard: View {
    let title: String
    let value: String
    let subtitle: String
    let points: [ActivityViewModel.MetricPoint]
    let tint: Color
    /// Fixed y-axis range, or `nil` to autoscale (used for byte rates).
    let yDomain: ClosedRange<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.text)
                .contentTransition(.numericText())
            chart
                .frame(height: 44)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var chart: some View {
        Chart(points) { point in
            AreaMark(x: .value("t", point.index), y: .value("v", point.value))
                .foregroundStyle(tint.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", point.index), y: .value("v", point.value))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain ?? autoDomain)
        .animation(.easeOut(duration: 0.25), value: points.last?.index)
    }

    /// Headroom above the observed peak so a flat-zero series still renders.
    private var autoDomain: ClosedRange<Double> {
        let peak = points.map(\.value).max() ?? 1
        return 0...max(peak * 1.2, 1)
    }
}

// MARK: - Pressure gauge card

private struct PressureCard: View {
    let stats: MachineResourceStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Memory Pressure")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
            Text(valueText)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Gauge(value: stats.hasMemoryPressure ? min(stats.memoryPressurePercent, 100) : 0, in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(tint)
            .frame(height: 44)
            .opacity(stats.hasMemoryPressure ? 1 : 0.35)
            Text(stats.hasMemoryPressure ? "PSI full avg10" : "PSI unavailable (no CONFIG_PSI)")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var valueText: String {
        stats.hasMemoryPressure ? StatsFormat.percent(stats.memoryPressurePercent) : "n/a"
    }

    /// Green under light pressure, amber past 10%, red past 40% — matching
    /// the daemon's own pressure thresholds.
    private var tint: Color {
        guard stats.hasMemoryPressure else { return AppColors.textMuted }
        switch stats.memoryPressurePercent {
        case ..<10: return AppColors.running
        case ..<40: return AppColors.warning
        default: return AppColors.error
        }
    }
}

// MARK: - Container table

private struct ContainerStatsHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            cell("CONTAINER", width: nil, alignment: .leading)
            cell("CPU", width: 64, alignment: .trailing)
            cell("MEMORY", width: 96, alignment: .trailing)
            cell("DISK R/W", width: 128, alignment: .trailing)
            cell("PIDS", width: 48, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(AppColors.sectionHeader)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func cell(_ text: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(text)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

private struct ContainerStatsRow: View {
    let container: ContainerResourceStats

    var body: some View {
        HStack(spacing: 12) {
            Text(container.displayName)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(StatsFormat.percent(container.cpuPercent))
                .frame(width: 64, alignment: .trailing)
            Text(memoryText)
                .frame(width: 96, alignment: .trailing)
            Text(
                "\(StatsFormat.rate(container.diskReadBytesPerSecond)) / \(StatsFormat.rate(container.diskWriteBytesPerSecond))"
            )
            .frame(width: 128, alignment: .trailing)
            Text("\(container.pids)")
                .frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var memoryText: String {
        if container.memoryLimitBytes == 0 {
            return StatsFormat.bytes(container.memoryCurrentBytes)
        }
        return
            "\(StatsFormat.bytes(container.memoryCurrentBytes)) / \(StatsFormat.bytes(container.memoryLimitBytes))"
    }
}

// MARK: - Formatting

/// Formatting for resource values, using `ByteCountFormatter` (memory
/// style) so sizes match Finder/Activity Monitor conventions.
enum StatsFormat {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let clamped = Int64(max(0, bytesPerSecond).rounded())
        return ByteCountFormatter.string(fromByteCount: clamped, countStyle: .memory) + "/s"
    }
}
