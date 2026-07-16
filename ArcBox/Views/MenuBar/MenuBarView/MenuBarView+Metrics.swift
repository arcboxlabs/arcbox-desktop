import ArcBoxClient
import SwiftUI

extension MenuBarView {
    // MARK: - Live Stats

    /// Compact live CPU / memory tiles, fed by the stats stream while the
    /// popover is open. Tapping either opens the full Activity Monitor.
    var liveStatsRow: some View {
        HStack(spacing: 6) {
            liveMetricTile(
                title: "CPU",
                symbol: "cpu",
                percent: activityVM.current?.cpuPercent,
                tint: .green
            )
            liveMetricTile(
                title: "Memory",
                symbol: "memorychip",
                percent: activityVM.current?.memoryUsedPercent,
                tint: .accentColor
            )
        }
        .padding(.bottom, 2)
    }

    func liveMetricTile(
        title: String,
        symbol: String,
        percent: Double?,
        tint: Color
    ) -> some View {
        Button {
            navigateToPage(.activity)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(percent.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentTransition(.numericText())

                Gauge(value: min(max(percent ?? 0, 0), 100), in: 0...100) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
                .opacity(percent == nil ? 0.3 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.30))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metric Cards

    var metricCards: some View {
        HStack(spacing: 6) {
            metricCard(
                title: "Volumes",
                count: volumesVM.volumes.count,
                symbol: "internaldrive",
                tint: .mint
            ) {
                navigateToPage(.volumes)
            }

            metricCard(
                title: "Images",
                count: imagesVM.images.count,
                symbol: "circle.circle",
                tint: .indigo
            ) {
                navigateToPage(.images)
            }

            metricCard(
                title: "Networks",
                count: networksVM.networks.count,
                symbol: "point.3.filled.connected.trianglepath.dotted",
                tint: .cyan
            ) {
                navigateToPage(.networks)
            }
        }
        .padding(.bottom, 2)
    }

    func metricCard(
        title: String,
        count: Int,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.30))
            )
        }
        .buttonStyle(.plain)
    }

}
