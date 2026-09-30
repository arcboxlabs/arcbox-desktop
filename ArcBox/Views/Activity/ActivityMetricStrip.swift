import ArcBoxClient
import SwiftUI

/// The machine-wide metric bar that floats over the container table.
///
/// One glass surface holds every tile. Liquid Glass is a single functional
/// layer: a pane per tile would stack glass on glass, and the tiles are one
/// bar, not four floating controls.
struct ActivityMetricStrip: View {
    /// `nil` until the first usable frame. The tiles then render
    /// representatively-shaped stand-ins for the caller to redact, so the strip
    /// reaches its real size immediately and nothing moves when the numbers
    /// arrive.
    let stats: MachineResourceStats?
    let cpuHistory: [ActivityViewModel.MetricPoint]
    let memoryHistory: [ActivityViewModel.MetricPoint]
    let networkHistory: [ActivityViewModel.MetricPoint]

    var body: some View {
        ActivityMetricTiles(
            stats: stats,
            cpuHistory: cpuHistory,
            memoryHistory: memoryHistory,
            networkHistory: networkHistory
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface()
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

/// The strip's tiles without the glass around them — the part that changes
/// when a figure's rendering does, and so the part a review render captures.
struct ActivityMetricTiles: View {
    let stats: MachineResourceStats?
    let cpuHistory: [ActivityViewModel.MetricPoint]
    let memoryHistory: [ActivityViewModel.MetricPoint]
    let networkHistory: [ActivityViewModel.MetricPoint]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 20)],
            alignment: .leading,
            spacing: 14
        ) {
            SparklineTile(
                title: "CPU",
                points: cpuHistory,
                tint: MetricTint.cpu,
                domain: 0...100,
                liveValue: stats.map { StatsFormat.percent($0.cpuPercent) } ?? "00%",
                liveCaption: stats.map { "\($0.onlineCPUs) cores · load \(StatsFormat.load($0.loadaverage1))" }
                    ?? "0 cores · load 0.00",
                format: StatsFormat.percent
            )

            SparklineTile(
                title: "Memory",
                points: memoryHistory,
                tint: MetricTint.memory,
                domain: 0...100,
                liveValue: stats.map { StatsFormat.percent($0.memoryUsedPercent) } ?? "00%",
                liveCaption: stats.map {
                    "\(StatsFormat.bytes($0.memoryUsedBytes)) of \(StatsFormat.bytes($0.memoryTotalBytes))"
                } ?? "0 GB of 0 GB",
                format: StatsFormat.percent
            )

            SparklineTile(
                title: "Network",
                points: networkHistory,
                tint: MetricTint.network,
                domain: nil,
                liveValue: stats.map {
                    StatsFormat.rate($0.networkReceiveBytesPerSecond + $0.networkTransmitBytesPerSecond)
                } ?? "0 MB/s",
                liveCaption: stats.map {
                    "↓ \(StatsFormat.rate($0.networkReceiveBytesPerSecond))  ↑ \(StatsFormat.rate($0.networkTransmitBytesPerSecond))"
                } ?? "↓ 0 MB/s  ↑ 0 MB/s",
                format: StatsFormat.rate
            )

            PressureTile(stats: stats)
        }
    }
}

/// Sparkline hues. System colors, so they track the appearance and the
/// increase-contrast setting; deliberately not the accent color, which means
/// "interactive" everywhere else in the app, and deliberately three distinct
/// hues so no two trends read as the same series.
private enum MetricTint {
    static let cpu = Color.green
    static let memory = Color.blue
    static let network = Color.purple
}

// MARK: - Tiles

/// A metric with history. Selecting a point on the sparkline rewinds the
/// headline to that sample and says how long ago it was, which is the whole
/// reason to keep a minute of history on screen rather than just the latest
/// number. Pointing at the figure selects, as `chartXSelection` did on the Mac;
/// leaving it lets go.
private struct SparklineTile: View {
    let title: LocalizedStringKey
    let points: [ActivityViewModel.MetricPoint]
    let tint: Color
    /// Fixed y range, or `nil` to autoscale (used for byte rates).
    let domain: ClosedRange<Double>?
    let liveValue: String
    let liveCaption: String
    let format: (Double) -> String

    @State private var scrubbedIndex: Int?

    var body: some View {
        MetricTile(
            title: title,
            value: scrubbed.map { format($0.value) } ?? liveValue,
            caption: scrubbed.map(elapsedCaption) ?? liveCaption,
            // Tinting only while scrubbing marks the headline as a reading from
            // the past rather than the live value.
            valueColor: scrubbed == nil ? AppColors.text : tint
        ) {
            Sparkline(points: points, tint: tint, domain: domain, scrubbedIndex: $scrubbedIndex)
        }
    }

    private var scrubbed: ActivityViewModel.MetricPoint? {
        scrubbedIndex.flatMap { index in points.first { $0.index == index } }
    }

    /// Guest-clock distance from the newest sample. Reported from the timestamps
    /// rather than the sample count, so a stalled or throttled stream doesn't
    /// quietly misreport the age.
    private func elapsedCaption(_ point: ActivityViewModel.MetricPoint) -> String {
        guard let latest = points.last, latest.monotonicMs > point.monotonicMs else {
            return "latest sample"
        }
        let seconds = Int((latest.monotonicMs - point.monotonicMs) / 1000)
        return seconds < 1 ? "latest sample" : "\(seconds)s ago"
    }
}

/// Label, headline number, a figure (sparkline or gauge) and a caption, at the
/// one shape every tile in the strip shares.
private struct MetricTile<Figure: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: LocalizedStringKey
    let value: String
    let caption: String
    var valueColor: Color = AppColors.text
    @ViewBuilder var figure: Figure

    var body: some View {
        // Label and caption share one tint and separate by weight and size.
        // Reaching for `.tertiary` instead would stack a faint grey on a
        // translucent surface with content moving behind it, which is where
        // legibility goes first.
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                // The label is known before the sample is; redacting it would
                // claim the screen knows less than it does.
                .unredacted()
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(valueColor)
                .liveValueAnimation(value)
            figure
                .frame(height: 30)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Motion

extension View {
    /// Settles a value that the stream, not the user, changed.
    ///
    /// Critically damped, because nothing here was thrown: overshoot belongs to
    /// motion a gesture handed momentum to. Dropped outright under Reduce
    /// Motion — SwiftUI adapts its own transitions for that setting, but not
    /// animations you write.
    fileprivate func liveValueAnimation<V: Equatable>(_ value: V) -> some View {
        modifier(LiveValueAnimation(value: value))
    }
}

private struct LiveValueAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
    }
}

// MARK: - Figures

/// A filled line over the rolling history, scrubbable with the pointer. The
/// tile's headline carries the value in text, so the figure itself stays out of
/// the accessibility tree rather than announcing sixty unlabelled samples.
///
/// Drawn with `Canvas` rather than Swift Charts. A `Chart` re-resolves every
/// mark through its scales on every sample: three of them cost 4.4 ms of
/// main-thread time per tick (measured 2026-10-01, `ActivityTickBenchmarkTests`),
/// the App Hangs Sentry filed as ARCBOX-DESKTOP-SWIFT-3G. Two paths through
/// sixty points cost microseconds. The pointer maps back to a sample through
/// `SparklineGeometry`, which is where the layout rules live.
private struct Sparkline: View {
    let points: [ActivityViewModel.MetricPoint]
    let tint: Color
    /// Fixed y range, or `nil` to autoscale (used for byte rates).
    let domain: ClosedRange<Double>?
    @Binding var scrubbedIndex: Int?

    /// The width the last layout gave the figure, so a pointer position can be
    /// read back as a sample.
    @State private var width: CGFloat = 0

    /// The two diameters are Charts' `symbolSize` 16 and 40 — areas, in points
    /// squared — so the marker keeps the size it had.
    private static let markerDiameter: CGFloat = 4.5
    private static let scrubbingMarkerDiameter: CGFloat = 7
    /// The canvas reaches this far past the figure on every side so a marker
    /// on the newest sample, or on a sample at the top of the range, is drawn
    /// whole rather than clipped at the edge, as the chart's symbol was.
    private static let overflow = scrubbingMarkerDiameter / 2

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: Self.overflow, y: Self.overflow)
            let size = CGSize(width: size.width - 2 * Self.overflow, height: size.height - 2 * Self.overflow)
            let values = points.map(\.value)
            let geometry = SparklineGeometry(
                values: values,
                domain: domain ?? SparklineGeometry.autoDomain(for: values),
                size: size
            )
            context.fill(
                geometry.area,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.35), tint.opacity(0.02)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(
                geometry.line,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )

            // The marker follows the pointer while scrubbing and returns to the
            // newest sample when it leaves, so there is always exactly one.
            guard let offset = markedOffset, offset < geometry.points.count else { return }
            let marked = geometry.points[offset]
            if scrubbedIndex != nil {
                var rule = Path()
                rule.move(to: CGPoint(x: marked.x, y: 0))
                rule.addLine(to: CGPoint(x: marked.x, y: size.height))
                context.stroke(rule, with: .color(tint.opacity(0.35)), style: StrokeStyle(lineWidth: 1))
            }
            let diameter = scrubbedIndex == nil ? Self.markerDiameter : Self.scrubbingMarkerDiameter
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: marked.x - diameter / 2, y: marked.y - diameter / 2,
                        width: diameter, height: diameter)),
                with: .color(tint)
            )
        }
        .padding(-Self.overflow)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width - 2 * Self.overflow
        } action: {
            width = $0
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): scrub(atX: location.x - Self.overflow)
            case .ended: scrubbedIndex = nil
            }
        }
        // Hover stops reporting while the button is down; a press-and-drag
        // scrubs through the gesture instead.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { scrub(atX: $0.location.x - Self.overflow) }
        )
        .accessibilityHidden(true)
    }

    /// Position in `points` of the marked sample: the scrubbed one while it is
    /// still on screen, otherwise the newest.
    private var markedOffset: Int? {
        guard let scrubbedIndex,
            let offset = points.firstIndex(where: { $0.index == scrubbedIndex })
        else {
            return points.indices.last
        }
        return offset
    }

    private func scrub(atX x: CGFloat) {
        guard let offset = SparklineGeometry.sampleOffset(atX: x, count: points.count, width: width) else {
            return
        }
        scrubbedIndex = points[offset].index
    }
}

/// PSI memory pressure. Green under light pressure, amber past 10%, red past
/// 40% — the daemon's own thresholds.
private struct PressureTile: View {
    let stats: MachineResourceStats?

    var body: some View {
        MetricTile(
            title: "Memory Pressure",
            value: value,
            caption: caption,
            valueColor: tint
        ) {
            Gauge(value: level, in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(tint)
            .opacity(stats?.hasMemoryPressure == false ? 0.35 : 1)
            .liveValueAnimation(level)
        }
    }

    private var value: String {
        guard let stats else { return "00%" }
        return stats.hasMemoryPressure ? StatsFormat.percent(stats.memoryPressurePercent) : "n/a"
    }

    private var caption: String {
        guard let stats else { return "PSI full avg10" }
        return stats.hasMemoryPressure ? "PSI full avg10" : "PSI unavailable (no CONFIG_PSI)"
    }

    private var level: Double {
        guard let stats, stats.hasMemoryPressure else { return 0 }
        return min(stats.memoryPressurePercent, 100)
    }

    private var tint: Color {
        guard let stats, stats.hasMemoryPressure else { return AppColors.textMuted }
        switch stats.memoryPressurePercent {
        case ..<10: return AppColors.running
        case ..<40: return AppColors.warning
        default: return AppColors.error
        }
    }
}
