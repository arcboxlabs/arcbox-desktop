import SwiftUI

/// Column 2: this Mac as a fleet runner host — status bar on top, job list below (RUN-11).
struct RunnersView: View {
    @Environment(RunnersViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            if let host = vm.host {
                RunnerHostStatusBar(host: host, isDraining: Bindable(vm).isDraining)
                jobsPlaceholder
            } else {
                RunnerEmptyState(onConnect: { vm.connect() })
            }
        }
        .background(AppColors.background)
        .navigationTitle("This Mac")
        .navigationSubtitle(subtitle)
        .onAppear {
            #if DEBUG
                if vm.host == nil {
                    vm.loadSampleData()
                }
            #endif
        }
    }

    private var subtitle: String {
        guard let host = vm.host else { return "Not connected" }
        let jobs = vm.activeJobCount == 1 ? "1 active job" : "\(vm.activeJobCount) active jobs"
        return "\(host.status.label) · \(jobs)"
    }

    private var jobsPlaceholder: some View {
        EmptyStateView(icon: "play.square.stack", title: "No jobs yet") {
            Text("Workflow jobs dispatched to this Mac will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
