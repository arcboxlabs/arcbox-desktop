import SwiftUI

struct RunnerJobDetailView: View {
    let job: RunnerJobDetailModel

    @State private var activeTab: RunnerJobDetailTab = .info

    var body: some View {
        Group {
            switch activeTab {
            case .info:
                RunnerJobInfoTab(job: job)
            case .logs:
                RunnerJobLogsTab(job: job)
            case .runtime:
                RunnerJobRuntimeTab(job: job)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Job detail", selection: $activeTab) {
                    ForEach(RunnerJobDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }

            if let githubURL = job.githubURL {
                ToolbarItem {
                    Link(destination: githubURL) {
                        Label("Open in GitHub", systemImage: "arrow.up.forward.square")
                    }
                    .help("Open this job in GitHub Actions")
                }
            }
        }
    }
}
