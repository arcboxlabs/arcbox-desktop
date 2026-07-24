import FleetPlatformClient
import SwiftUI

struct RunnerSelectionDetailView: View {
    @Environment(RunnerPlatformStore.self) private var store

    var body: some View {
        switch store.selection {
        case .host:
            ContentUnavailableView {
                Label(store.machine?.name ?? "This Mac", systemImage: "desktopcomputer")
            } description: {
                Text("Host details are not implemented yet.")
            }
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

    private func selectedJobTitle(jobID: String) -> String {
        store.jobs.first(where: { $0.id == jobID })?.repo ?? jobID
    }
}
