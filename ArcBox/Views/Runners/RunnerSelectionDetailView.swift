import FleetControlClient
import FleetPlatformClient
import SwiftUI

struct RunnerSelectionDetailView: View {
    @Environment(RunnerPlatformStore.self) private var store
    @Environment(RunnersViewModel.self) private var runners

    var body: some View {
        switch store.selection {
        case .host:
            hostDetail
        case .job(let jobID):
            if let job = selectedJob(id: jobID) {
                RunnerJobDetailView(job: job)
            } else {
                ContentUnavailableView {
                    Label("Job unavailable", systemImage: "hammer")
                } description: {
                    Text("This job is no longer reported by Platform or the local Fleet Agent.")
                }
            }
        case nil:
            DetailPlaceholderView()
        }
    }

    @ViewBuilder
    private var hostDetail: some View {
        if case .enrolled(let host, _) = runners.viewState {
            RunnerHostDetailView(host: host)
        } else {
            ContentUnavailableView {
                Label("Host unavailable", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            } description: {
                Text("ArcBox is waiting for a conclusive Fleet Agent state.")
            }
        }
    }

    private func selectedJob(id: String) -> RunnerJobDetailModel? {
        let liveJobs: [FleetInFlightJob] =
            if case .enrolled(let host, _) = runners.viewState {
                host.inFlightJobs
            } else {
                []
            }
        return RunnerJobDetailModel.resolve(
            id: id,
            platformJobs: store.jobs,
            liveJobs: liveJobs
        )
    }
}
