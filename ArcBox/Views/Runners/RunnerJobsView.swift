import SwiftUI

struct RunnerJobsView: View {
    let jobs: [RunnerJobListItem]
    let platformLoadState: RunnerPlatformLoadState
    let selectedJobID: String?
    let onSelect: (String) -> Void

    var body: some View {
        if jobs.isEmpty {
            emptyContent
        } else {
            VStack(spacing: 0) {
                if case .failed(let message) = platformLoadState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                List(jobs) { job in
                    RunnerJobRow(
                        job: job,
                        isSelected: selectedJobID == job.id,
                        onSelect: { onSelect(job.id) }
                    )
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch platformLoadState {
        case .loading:
            ProgressView("Loading job history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyStateView(icon: "exclamationmark.triangle", title: "Could not load job history") {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        case .machineNotFound:
            EmptyStateView(icon: "clock.arrow.circlepath", title: "Waiting for job history") {
                Text("This machine has not appeared in the Platform workspace yet.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        case .idle, .loaded:
            EmptyStateView(icon: "play.square.stack", title: "No jobs") {
                Text("Workflow jobs dispatched to this Mac will appear here.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
