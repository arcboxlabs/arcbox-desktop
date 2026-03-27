import SwiftUI

/// Metric card matching the E2B monitoring dashboard style
struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    var limit: Int? = nil
    var isLive: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Live badge
            if isLive {
                StatusBadge(color: AppColors.running, label: "LIVE")
            }

            // Value
            Text(value)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.text)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)

            // Limit
            if let limit {
                Text("LIMIT: \(limit)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
    }
}

/// Chart placeholder matching the E2B monitoring style
struct MonitoringChart: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .textCase(.uppercase)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.text)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .textCase(.uppercase)
                    }
                }

                Spacer()

                StatusBadge(color: AppColors.running, label: "LIVE")
            }

            // Chart area placeholder
            ZStack {
                // Grid lines
                VStack(spacing: 0) {
                    ForEach(0..<4) { _ in
                        Divider()
                            .overlay(AppColors.borderSubtle)
                        Spacer()
                    }
                    Divider()
                        .overlay(AppColors.borderSubtle)
                }

                // Flat line at bottom (zero data)
                GeometryReader { geo in
                    Path { path in
                        let y = geo.size.height - 2
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(AppColors.running, lineWidth: 2)

                    // End dot
                    Circle()
                        .fill(AppColors.running)
                        .frame(width: 8, height: 8)
                        .position(x: geo.size.width - 4, y: geo.size.height - 2)
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
    }
}

/// Sandbox monitoring dashboard view
struct SandboxMonitoringView: View {
    let vm: SandboxesViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Top metric cards
                HStack(spacing: 16) {
                    MetricCard(
                        title: "Concurrent Sandboxes",
                        value: "\(vm.concurrentSandboxes)",
                        subtitle: "Concurrent Sandboxes\n(5-sec avg)",
                        limit: vm.concurrentLimit
                    )
                    MetricCard(
                        title: "Start Rate",
                        value: String(format: "%.3f", vm.startRatePerSecond),
                        subtitle: "Start Rate Per Second\n(5-sec rolling avg)",
                        isLive: false
                    )
                    MetricCard(
                        title: "Peak Concurrent",
                        value: "\(vm.peakConcurrentSandboxes)",
                        subtitle: "Peak Concurrent Sandboxes\n(session max)",
                        limit: vm.concurrentLimit,
                        isLive: false
                    )
                }

                // Charts
                MonitoringChart(
                    title: "Concurrent Sandboxes",
                    value: "\(vm.concurrentSandboxes)",
                    subtitle: "Average"
                )

                MonitoringChart(
                    title: "Start Rate Per Second",
                    value: String(format: "%.3f", vm.startRatePerSecond),
                    subtitle: "Average"
                )
            }
            .padding(16)
        }
        .background(AppColors.background)
    }
}
