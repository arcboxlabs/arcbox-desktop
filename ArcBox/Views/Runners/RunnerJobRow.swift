import FleetControlClient
import SwiftUI

struct RunnerJobRow: View {
    let job: FleetInFlightJob

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.os == "darwin" ? "macwindow" : "shippingbox")
                .foregroundStyle(AppColors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.jobID)
                    .font(.body.monospaced())
                    .lineLimit(1)
                Text("\(job.os)/\(job.arch)")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            StatusBadge(color: AppColors.running, label: "Running")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
