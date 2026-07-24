import SwiftUI

struct RunnerJobLogsTab: View {
    let job: RunnerJobDetailModel

    var body: some View {
        ContentUnavailableView {
            Label("Job logs unavailable", systemImage: "terminal")
        } description: {
            Text(
                "Fleet Platform and the local Fleet Agent do not currently expose a job log stream to ArcBox Desktop."
            )
        } actions: {
            if let githubURL = job.githubURL {
                Link(destination: githubURL) {
                    Label("View logs in GitHub", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
