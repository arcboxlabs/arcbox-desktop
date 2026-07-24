import SwiftUI

struct RunnerHostOverviewJobsSection: View {
    let summary: RunnerHostJobSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job activity")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    metric(title: "Today", value: summary.todayCount.formatted())
                    metric(title: "Recorded", value: summary.recordedCountDescription)
                    metric(title: "Success rate", value: successRateDescription)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .infoSectionStyle()

            if summary.hasMoreHistory {
                Label(
                    "Metrics use the most recent loaded Platform history.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var successRateDescription: String {
        guard let successRate = summary.successRate else { return "—" }
        return successRate.formatted(.percent.precision(.fractionLength(0)))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
