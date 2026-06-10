import SwiftUI
import os

@MainActor
@Observable
class RunnersViewModel {
    /// The enrolled fleet host record for this Mac; nil until enrollment completes.
    var host: RunnerHostViewModel?

    var isEnrolled: Bool { host != nil }

    /// Jobs currently occupying slots across both runtime pools.
    var activeJobCount: Int { host?.activeJobCount ?? 0 }

    /// Settable so the drain switch can bind via `Bindable(vm).isDraining`.
    var isDraining: Bool {
        get { host?.status == .draining }
        set { setDraining(newValue) }
    }

    // MARK: - Actions (wired to the platform REST client once RUN-8 lands)

    func connect() {
        Log.runner.warning("Not implemented: \(#function) — web handoff arrives with RUN-8")
    }

    private func setDraining(_ draining: Bool) {
        guard var host, host.status != .offline else { return }
        host.status = draining ? .draining : .online
        self.host = host
        Log.runner.warning("Not implemented: \(#function) — platform call arrives with RUN-13")
    }

    func loadSampleData() {
        host = SampleData.runnerHost
    }
}
