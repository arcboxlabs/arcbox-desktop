import ArcBoxAuth
import FleetControlClient
import FleetPlatformClient
import Observation

@MainActor
protocol FleetWorkspaceListing: Sendable {
    func listWorkspaces() async throws -> [FleetWorkspace]
}

extension FleetPlatformClient: FleetWorkspaceListing {}

@MainActor
@Observable
final class RunnersViewModel {
    let fleet: FleetViewModel
    private(set) var workspaces: [FleetWorkspace] = []
    private(set) var platformError: String?
    private(set) var isLoadingWorkspaces = false

    @ObservationIgnored
    private var platformClient: (any FleetWorkspaceListing)?

    @ObservationIgnored
    private var enrollmentCoordinator: FleetEnrollmentCoordinator?

    @ObservationIgnored
    private var activeControlClient: FleetControlClient?

    @ObservationIgnored
    private var activePlatformClient: FleetPlatformClient?

    @ObservationIgnored
    private var hasStarted = false

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

    var errorMessage: String? {
        platformError ?? enrollmentCoordinator?.errorMessage ?? fleet.lastError
    }

    var isBusy: Bool {
        isLoadingWorkspaces || fleet.isPerformingAction || enrollmentCoordinator?.isBusy == true
    }

    var canConnect: Bool {
        !isBusy && enrollmentCoordinator?.canBeginEnrollment == true
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
        platformClient: FleetPlatformClient?,
        authentication: (any FleetAuthenticationChecking)? = nil,
        agentReadiness: (any FleetAgentReadying)? = nil
    ) {
        self.platformClient = platformClient

        if enrollmentCoordinator == nil || activePlatformClient !== platformClient {
            if let authentication, let agentReadiness, let platformClient {
                enrollmentCoordinator = FleetEnrollmentCoordinator(
                    authentication: authentication,
                    agentReadiness: agentReadiness,
                    tokenIssuer: platformClient
                )
            } else {
                enrollmentCoordinator = nil
            }
        }

        guard
            !hasStarted
                || activeControlClient !== controlClient
                || activePlatformClient !== platformClient
        else { return }

        hasStarted = true
        activeControlClient = controlClient
        activePlatformClient = platformClient
        let coordinator = enrollmentCoordinator
        fleet.start(
            client: controlClient,
            onSnapshot: { [weak coordinator] snapshot in
                coordinator?.reconcile(snapshot)
            }
        )
    }

    func stop() {
        enrollmentCoordinator?.cancel()
        fleet.stop()
        hasStarted = false
        activeControlClient = nil
        activePlatformClient = nil
    }

    func prepareForTermination(gracePeriod: Duration = .seconds(65)) async -> Bool {
        let settled =
            await enrollmentCoordinator?.settleForTermination(
                gracePeriod: gracePeriod
            ) ?? true
        fleet.stop()
        return settled
    }

    func prepareEnrollment() async -> Bool {
        platformError = nil
        guard let enrollmentCoordinator else {
            platformError = "Fleet enrollment is unavailable."
            return false
        }
        guard enrollmentCoordinator.canBeginEnrollment else { return false }
        guard enrollmentCoordinator.requireSignedIn() else { return false }
        guard let platformClient else {
            platformError = "Fleet Platform client is unavailable."
            return false
        }

        isLoadingWorkspaces = true
        platformError = nil
        defer { isLoadingWorkspaces = false }

        do {
            workspaces = try await platformClient.listWorkspaces()
        } catch {
            platformError = FleetPlatformClient.userMessage(for: error)
            return false
        }

        guard !workspaces.isEmpty else {
            platformError = "No ArcBox workspace is available for this account."
            return false
        }
        return true
    }

    @discardableResult
    func enroll(in workspace: FleetWorkspace) async -> Bool {
        platformError = nil
        guard let enrollmentCoordinator else {
            platformError = "Fleet enrollment is unavailable."
            return false
        }

        let succeeded = await enrollmentCoordinator.enroll(workspaceID: workspace.id)
        if succeeded {
            platformError = nil
        }
        return succeeded
    }

    @discardableResult
    func setDraining(_ draining: Bool) async -> Bool {
        if draining {
            await fleet.drain()
        } else {
            await fleet.resume()
        }
    }

    @discardableResult
    func unenroll() async -> Bool {
        guard !isBusy else { return false }
        let succeeded = await fleet.unenroll()
        if succeeded {
            enrollmentCoordinator?.confirmUnenrolled()
            if let snapshot = fleet.snapshot {
                enrollmentCoordinator?.reconcile(snapshot)
            }
        }
        return succeeded
    }
}
