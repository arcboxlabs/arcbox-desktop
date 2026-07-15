import ArcBoxAuth
import FleetControlClient
import FleetPlatformClient
import Foundation
import Observation

@MainActor
protocol FleetWorkspaceListing: Sendable {
    func listWorkspaces() async throws -> [FleetWorkspace]
}

extension FleetPlatformClient: FleetWorkspaceListing {}

@MainActor
@Observable
final class RunnersViewModel {
    struct EnrollmentContext: Equatable {
        let state: FleetEnrollmentCoordinator.State
        let isSignedIn: Bool
        let canBeginEnrollment: Bool
    }

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
        Self.resolveViewState(
            snapshot: fleet.snapshot,
            agentInfo: fleet.agentInfo,
            loadState: fleet.loadState,
            enrollmentContext: enrollmentContext
        )
    }

    private var enrollmentContext: EnrollmentContext? {
        guard let enrollmentCoordinator else { return nil }
        return EnrollmentContext(
            state: enrollmentCoordinator.state,
            isSignedIn: enrollmentCoordinator.isSignedIn,
            canBeginEnrollment: enrollmentCoordinator.canBeginEnrollment
        )
    }

    var activeJobCount: Int {
        fleet.snapshot?.inFlightJobs.count ?? 0
    }

    var errorMessage: String? {
        platformError ?? fleet.lastError ?? enrollmentCoordinator?.errorMessage
    }

    var isBusy: Bool {
        isLoadingWorkspaces || fleet.isPerformingAction || enrollmentCoordinator?.isBusy == true
    }

    var canConnect: Bool {
        !isBusy && enrollmentCoordinator?.canBeginEnrollment == true
    }

    var subtitle: String {
        switch viewState {
        case .connecting: return "Connecting"
        case .unavailable: return "Agent unavailable"
        case .signedOut: return "Sign in required"
        case .unenrolled: return "Not connected"
        case .enrolling(let progress): return progress.title
        case .enrollmentFailed: return "Enrollment failed"
        case .failed: return "Fleet integration unavailable"
        case .enrolled(let host, let freshness):
            if case .reconnecting = freshness {
                return "Reconnecting to Fleet Agent"
            }
            return host.activeJobCount == 1
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
        guard !isBusy else { return false }

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
        guard !isBusy else { return false }

        if draining {
            return await fleet.drain()
        } else {
            return await fleet.resume()
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

    static func resolveViewState(
        snapshot: FleetAgentSnapshot?,
        agentInfo: FleetAgentInfo?,
        loadState: FleetLoadState,
        enrollmentContext: EnrollmentContext?
    ) -> RunnersViewState {
        if let snapshot {
            switch snapshot.enrollment {
            case .attaching, .attached, .detached, .credentialRejected:
                guard normalizedMachineID(snapshot.machineID) != nil else {
                    return .failed("Fleet Agent reported an invalid machine identity.")
                }
                return .enrolled(
                    RunnerHostViewModel(snapshot: snapshot, agentInfo: agentInfo),
                    freshness: hostFreshness(loadState: loadState)
                )
            case .unenrolled:
                guard normalizedMachineID(snapshot.machineID) == nil else {
                    return .failed("Fleet Agent reported an invalid unenrolled state.")
                }
                switch loadState {
                case .idle, .connecting:
                    return .connecting
                case .unavailable(let message), .failed(let message):
                    return .unavailable(message)
                case .ready:
                    break
                }
                return resolveUnenrolledState(
                    enrollmentContext: enrollmentContext
                )
            case .unspecified:
                return .failed("Fleet Agent did not report a valid enrollment state.")
            case .unrecognized:
                return .failed(
                    "Fleet Agent reported an enrollment state this ArcBox version does not support."
                )
            }
        }

        switch loadState {
        case .idle, .connecting, .ready:
            return .connecting
        case .unavailable(let message), .failed(let message):
            return .unavailable(message)
        }
    }

    private static func resolveUnenrolledState(
        enrollmentContext: EnrollmentContext?
    ) -> RunnersViewState {
        guard let enrollmentContext else {
            return .failed("Fleet enrollment is unavailable for this build.")
        }

        switch enrollmentContext.state {
        case .preparingAgent:
            return .enrolling(.checkingAgent)
        case .requestingEnrollmentToken:
            return .enrolling(.requestingToken)
        case .enrolling:
            return .enrolling(.enrollingAgent)
        case .reconcilingEnrollment:
            return .enrolling(.reconciling)
        case .attaching:
            return .enrolling(.attaching)
        case .ready:
            return .enrolling(.synchronizing)
        case .failed(let failure):
            return .enrollmentFailed(
                failure.localizedDescription,
                recovery: enrollmentContext.canBeginEnrollment ? .retry : .waitForAgent
            )
        case .idle, .requiresSignIn:
            guard enrollmentContext.isSignedIn else { return .signedOut }
            guard enrollmentContext.canBeginEnrollment else {
                return .enrollmentFailed(
                    "ArcBox is waiting for the Fleet Agent to report a conclusive enrollment state.",
                    recovery: .waitForAgent
                )
            }
            return .unenrolled
        }
    }

    private static func hostFreshness(loadState: FleetLoadState) -> RunnerHostFreshness {
        switch loadState {
        case .ready:
            return .live
        case .idle, .connecting:
            return .reconnecting("Connecting to Fleet Agent.")
        case .unavailable(let message), .failed(let message):
            return .reconnecting(message)
        }
    }

    private static func normalizedMachineID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }
}
