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
            ContentUnavailableView {
                Label(selectedJobTitle(jobID: jobID), systemImage: "hammer")
            } description: {
                Text("Job details are not implemented yet.")
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

    private func selectedJobTitle(jobID: String) -> String {
        store.jobs.first(where: { $0.id == jobID })?.repo ?? jobID
    }
}
