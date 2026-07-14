import FleetControlClient
import FleetPlatformClient
import Observation

@MainActor
@Observable
final class RunnersViewModel {
    let fleet: FleetViewModel

    init(fleet: FleetViewModel = FleetViewModel()) {
        self.fleet = fleet
    }

    var viewState: RunnersViewState {
        if let snapshot = fleet.snapshot {
            switch snapshot.enrollment {
            case .attaching, .attached, .detached, .credentialRejected:
                return .enrolled(
                    RunnerHostViewModel(snapshot: snapshot, agentInfo: fleet.agentInfo)
                )
            case .unenrolled, .unspecified, .unrecognized:
                return .unenrolled
            }
        }

        switch fleet.loadState {
        case .idle, .connecting, .ready:
            return .connecting
        case .unavailable(let message), .failed(let message):
            return .unavailable(message)
        }
    }

    var activeJobCount: Int {
        fleet.snapshot?.inFlightJobs.count ?? 0
    }

    var workspaces: [FleetWorkspace] {
        fleet.workspaces
    }

    var errorMessage: String? {
        fleet.platformError ?? fleet.lastError
    }

    var isBusy: Bool {
        fleet.isLoadingWorkspaces || fleet.isPerformingAction
    }

    var subtitle: String {
        switch viewState {
        case .connecting: "Connecting"
        case .unavailable: "Agent unavailable"
        case .unenrolled: "Not connected"
        case .enrolled(let host):
            host.activeJobCount == 1
                ? "\(host.status.label) · 1 active job"
                : "\(host.status.label) · \(host.activeJobCount) active jobs"
        }
    }

    func start(
        controlClient: FleetControlClient?,
        platformClient: FleetPlatformClient?
    ) {
        fleet.start(client: controlClient, platformClient: platformClient)
    }

    func stop() {
        fleet.stop()
    }

    func prepareEnrollment() async -> Bool {
        guard await fleet.loadWorkspaces() else { return false }
        guard !fleet.workspaces.isEmpty else {
            fleet.platformError = "No ArcBox workspace is available for this account."
            return false
        }
        return true
    }

    @discardableResult
    func enroll(in workspace: FleetWorkspace) async -> Bool {
        await fleet.enroll(workspaceID: workspace.id)
    }

    @discardableResult
    func setDraining(_ draining: Bool) async -> Bool {
        if draining {
            await fleet.drain()
        } else {
            await fleet.resume()
        }
    }
}
