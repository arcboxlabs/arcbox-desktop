import FleetPlatformClient
import SwiftUI

struct RunnerHostOverviewTab: View {
    let host: RunnerHostViewModel
    let machine: FleetMachine?
    let workspace: FleetWorkspace?
    let jobs: [FleetRunnerJob]
    let hasMoreJobHistory: Bool

    var body: some View {
        let summary = RunnerHostJobSummary(
            jobs: jobs,
            hasMoreHistory: hasMoreJobHistory
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RunnerHostOverviewStatusSection(
                    host: host,
                    machine: machine,
                    workspace: workspace
                )
                RunnerHostOverviewJobsSection(summary: summary)
                RunnerHostOverviewPoolsSection(host: host)
            }
            .padding(16)
        }
    }
}
