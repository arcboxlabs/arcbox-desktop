import FleetControlClient
import SwiftUI

struct RunnerJobsView: View {
    let jobs: [FleetInFlightJob]

    var body: some View {
        if jobs.isEmpty {
            EmptyStateView(icon: "play.square.stack", title: "No active jobs") {
                Text("Workflow jobs dispatched to this Mac will appear here.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        } else {
            List(jobs) { job in
                RunnerJobRow(job: job)
            }
            .listStyle(.inset)
        }
    }
}
