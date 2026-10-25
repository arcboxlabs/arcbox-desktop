import ArcBoxAuth
import Foundation
import Observation
import PlatformClient
import RunnerAgentClient

@MainActor
protocol RunnerWorkspaceListing: Sendable {
    func listWorkspaces() async throws -> [PlatformWorkspace]
}

extension PlatformClient: RunnerWorkspaceListing {}

@MainActor
@Observable
final class RunnersViewModel {
    struct EnrollmentContext: Equatable {
        let state: RunnerEnrollmentCoordinator.State
        let isSignedIn: Bool
        let canBeginEnrollment: Bool
    }

    let agent: RunnerAgentViewModel
    private(set) var workspaces: [PlatformWorkspace] = []
    private(set) var platformError: String?
    private(set) var isLoadingWorkspaces = false

    @ObservationIgnored
    private var platformClient: (any RunnerWorkspaceListing)?

    @ObservationIgnored
    private var enrollmentCoordinator: RunnerEnrollmentCoordinator?

    @ObservationIgnored
    private var activeControlClient: RunnerAgentClient?

    @ObservationIgnored
    private var activePlatformClient: PlatformClient?

    @ObservationIgnored
    private var hasStarted = false

    init(agent: RunnerAgentViewModel = RunnerAgentViewModel()) {
        self.agent = agent
    }

    var viewState: RunnersViewState {
        Self.resolveViewState(
            snapshot: agent.snapshot,
            agentInfo: agent.agentInfo,
            loadState: agent.loadState,
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
        agent.snapshot?.inFlightJobs.count ?? 0
    }

    var errorMessage: String? {
        platformError ?? agent.lastError ?? enrollmentCoordinator?.errorMessage
    }

    var isBusy: Bool {
        isLoadingWorkspaces || agent.isPerformingAction || enrollmentCoordinator?.isBusy == true
    }

    var canConnect: Bool {
        !isBusy && enrollmentCoordinator?.canBeginEnrollment == true
    }

    var subtitle: String {
        switch viewState {
        case .connecting: return "Connecting"
        case .unavailable: return "Agent unavailable"
        case .signedOut: return "Not connected"
        case .unenrolled: return "Not connected"
        case .enrolling(let progress): return progress.title
        case .enrollmentFailed(_, let recovery):
            switch recovery {
            case .retry: return "Enrollment failed"
            case .waitForAgent: return "Confirming enrollment"
            case .unenroll: return "Enrollment needs attention"
            }
        case .failed: return "Runners unavailable"
        case .enrolled(let host, let freshness):
            if case .reconnecting = freshness {
                return "Reconnecting to Runner Agent"
            }
            return host.activeJobCount == 1
                ? "\(host.status.label) · 1 active job"
                : "\(host.status.label) · \(host.activeJobCount) active jobs"
        }
    }

    func start(
        controlClient: RunnerAgentClient?,
        platformClient: PlatformClient?,
        authentication: (any RunnerAuthenticationChecking)? = nil,
        agentReadiness: (any RunnerAgentReadying)? = nil
    ) {
        self.platformClient = platformClient

        if enrollmentCoordinator == nil || activePlatformClient !== platformClient {
            if let authentication, let agentReadiness {
                enrollmentCoordinator = RunnerEnrollmentCoordinator(
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
        agent.start(
            client: controlClient,
            onSnapshot: { [weak coordinator] snapshot in
                coordinator?.reconcile(snapshot)
            }
        )
    }

    func stop() {
        enrollmentCoordinator?.cancel()
        agent.stop()
        hasStarted = false
        activeControlClient = nil
        activePlatformClient = nil
    }

    func prepareForTermination(gracePeriod: Duration = .seconds(65)) async -> Bool {
        let settled =
            await enrollmentCoordinator?.settleForTermination(
                gracePeriod: gracePeriod
            ) ?? true
        agent.stop()
        return settled
    }

    func prepareEnrollment() async -> Bool {
        guard !isBusy else { return false }

        platformError = nil
        guard let enrollmentCoordinator else {
            platformError = "Runner enrollment is unavailable."
            return false
        }
        guard enrollmentCoordinator.canBeginEnrollment else { return false }
        guard enrollmentCoordinator.requireSignedIn() else { return false }
        guard let platformClient else {
            platformError = "Platform client is unavailable."
            return false
        }

        isLoadingWorkspaces = true
        platformError = nil
        defer { isLoadingWorkspaces = false }

        do {
            workspaces = try await platformClient.listWorkspaces()
        } catch {
            platformError = PlatformClient.userMessage(for: error)
            return false
        }

        guard !workspaces.isEmpty else {
            platformError = "No ArcBox workspace is available for this account."
            return false
        }
        return true
    }

    @discardableResult
    func enroll(in workspace: PlatformWorkspace) async -> Bool {
        platformError = nil
        guard let enrollmentCoordinator else {
            platformError = "Runner enrollment is unavailable."
            return false
        }

        let succeeded = await enrollmentCoordinator.enroll(workspaceID: workspace.id)
        if succeeded {
            platformError = nil
        }
        return succeeded
    }

    /// Enrolls with a caller-supplied token; the current Desktop UI does not expose this fallback.
    @discardableResult
    func enroll(withToken token: String) async -> Bool {
        platformError = nil
        guard let enrollmentCoordinator else {
            platformError = "Runner enrollment is unavailable."
            return false
        }

        return await enrollmentCoordinator.enroll(token: token)
    }

    @discardableResult
    func setDraining(_ draining: Bool) async -> Bool {
        guard !isBusy else { return false }

        if draining {
            return await agent.drain()
        } else {
            return await agent.resume()
        }
    }

    @discardableResult
    func unenroll() async -> Bool {
        guard !isBusy else { return false }
        let succeeded = await agent.unenroll()
        if succeeded {
            enrollmentCoordinator?.confirmUnenrolled()
            if let snapshot = agent.snapshot {
                enrollmentCoordinator?.reconcile(snapshot)
            }
        }
        return succeeded
    }

    static func resolveViewState(
        snapshot: RunnerAgentSnapshot?,
        agentInfo: RunnerAgentInfo?,
        loadState: RunnerAgentLoadState,
        enrollmentContext: EnrollmentContext?
    ) -> RunnersViewState {
        if let snapshot {
            switch snapshot.enrollment {
            case .attaching, .attached, .updating:
                if normalizedHostID(snapshot.hostID) == nil {
                    if let override = connectivityOverride(loadState: loadState) {
                        return override
                    }
                    return .failed("Runner Agent reported an invalid host identity.")
                }
                return .enrolled(
                    RunnerHostViewModel(snapshot: snapshot, agentInfo: agentInfo),
                    freshness: hostFreshness(loadState: loadState)
                )
            case .credentialRejected:
                if let override = connectivityOverride(loadState: loadState) {
                    return override
                }
                guard let hostID = normalizedHostID(snapshot.hostID) else {
                    return .failed("Runner Agent reported an invalid host identity.")
                }
                return .enrollmentFailed(
                    RunnerEnrollmentCoordinator.Failure.credentialRejected(hostID: hostID)
                        .localizedDescription,
                    recovery: .unenroll
                )
            case .detached:
                if let override = connectivityOverride(loadState: loadState) {
                    return override
                }
                guard let hostID = normalizedHostID(snapshot.hostID) else {
                    return .failed("Runner Agent reported an invalid host identity.")
                }
                return .enrollmentFailed(
                    RunnerEnrollmentCoordinator.Failure.detached(hostID: hostID)
                        .localizedDescription,
                    recovery: .unenroll
                )
            case .unenrolled:
                if let override = connectivityOverride(loadState: loadState) {
                    return override
                }
                guard normalizedHostID(snapshot.hostID) == nil else {
                    return .failed("Runner Agent reported an invalid unenrolled state.")
                }
                return resolveUnenrolledState(
                    enrollmentContext: enrollmentContext
                )
            case .unspecified:
                return connectivityOverride(loadState: loadState)
                    ?? .failed("Runner Agent did not report a valid enrollment state.")
            case .unrecognized:
                return connectivityOverride(loadState: loadState)
                    ?? .failed(
                        "Runner Agent reported an enrollment state this ArcBox version does not support."
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
            return .failed("Runner enrollment is unavailable for this build.")
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
                recovery: enrollmentRecovery(
                    for: failure,
                    canBeginEnrollment: enrollmentContext.canBeginEnrollment
                )
            )
        case .idle, .requiresSignIn:
            guard enrollmentContext.isSignedIn else { return .signedOut }
            guard enrollmentContext.canBeginEnrollment else {
                return .enrollmentFailed(
                    "ArcBox is waiting for the Runner Agent to report a conclusive enrollment state.",
                    recovery: .waitForAgent
                )
            }
            return .unenrolled
        }
    }

    /// Surfaces connectivity when a retained snapshot cannot be trusted while the watch is stale.
    private static func connectivityOverride(loadState: RunnerAgentLoadState) -> RunnersViewState? {
        switch loadState {
        case .idle, .connecting:
            return .connecting
        case .unavailable(let message), .failed(let message):
            return .unavailable(message)
        case .ready:
            return nil
        }
    }

    private static func hostFreshness(loadState: RunnerAgentLoadState) -> RunnerHostFreshness {
        switch loadState {
        case .ready:
            return .live
        case .idle, .connecting:
            return .reconnecting("Connecting to Runner Agent.")
        case .unavailable(let message), .failed(let message):
            return .reconnecting(message)
        }
    }

    private static func enrollmentRecovery(
        for failure: RunnerEnrollmentCoordinator.Failure,
        canBeginEnrollment: Bool
    ) -> RunnerEnrollmentRecovery {
        guard !canBeginEnrollment else { return .retry }

        switch failure {
        case .enrollmentOutcomeUnknown:
            return .waitForAgent
        case .credentialRejected, .detached, .stateStreamEnded, .stateStreamFailed,
            .attachmentTimedOut, .cancelled(hostID: .some):
            return .unenroll
        case .workspaceRequired, .enrollmentTokenRequired, .agentPreparationFailed,
            .enrollmentTokenRequestFailed, .cancelled(hostID: nil):
            return .waitForAgent
        }
    }

    private static func normalizedHostID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }
}
