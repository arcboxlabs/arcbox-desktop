import ArcBoxAuth
import Foundation
import Observation
import PlatformClient
import RunnerAgentClient

@MainActor
protocol RunnerAuthenticationChecking: Sendable {
    var isSignedIn: Bool { get }
}

extension AuthSession: RunnerAuthenticationChecking {
    var isSignedIn: Bool {
        status == .signedIn
    }
}

@MainActor
protocol RunnerEnrollmentTokenIssuing: Sendable {
    func createEnrollmentToken(workspaceID: String) async throws -> RunnerEnrollmentToken
}

extension PlatformClient: RunnerEnrollmentTokenIssuing {}

@MainActor
protocol RunnerAgentEnrollmentControlling: Sendable {
    func enroll(token: String, controlPlane: String?) async throws -> String
    func watchSnapshots() -> AsyncThrowingStream<RunnerAgentSnapshot, Error>
}

extension RunnerAgentClient: RunnerAgentEnrollmentControlling {}

@MainActor
protocol RunnerAgentReadying: Sendable {
    func ensureReady() async throws -> any RunnerAgentEnrollmentControlling
}

/// Coordinates Platform-issued and manually supplied Agent enrollment handoffs.
@MainActor
@Observable
final class RunnerEnrollmentCoordinator {
    enum State: Equatable, Sendable {
        case idle
        case requiresSignIn
        case preparingAgent
        case requestingEnrollmentToken
        case enrolling
        case reconcilingEnrollment
        case attaching(hostID: String)
        case ready(hostID: String)
        case failed(Failure)

        fileprivate var isInProgress: Bool {
            switch self {
            case .preparingAgent, .requestingEnrollmentToken, .enrolling,
                .reconcilingEnrollment, .attaching:
                true
            case .idle, .requiresSignIn, .ready, .failed:
                false
            }
        }
    }

    enum Failure: Error, Equatable, Sendable {
        case workspaceRequired
        case enrollmentTokenRequired
        case agentPreparationFailed(message: String)
        case enrollmentTokenRequestFailed(message: String)
        case enrollmentOutcomeUnknown
        case credentialRejected(hostID: String)
        case detached(hostID: String)
        case stateStreamEnded(hostID: String)
        case stateStreamFailed(hostID: String)
        case attachmentTimedOut(hostID: String)
        case cancelled(hostID: String?)
    }

    private(set) var state: State = .idle

    private struct ActiveEnrollment {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private enum EnrollmentSource: Sendable {
        case workspace(String)
        case token(String)
    }

    private enum SnapshotBaselineError: LocalizedError {
        case streamEnded
        case timedOut

        var errorDescription: String? {
            switch self {
            case .streamEnded:
                "Runner Agent stopped reporting state before its initial snapshot."
            case .timedOut:
                "Runner Agent did not report its initial state in time."
            }
        }
    }

    @ObservationIgnored
    private var activeEnrollment: ActiveEnrollment?

    @ObservationIgnored
    private var canCancelActiveEnrollment = false

    @ObservationIgnored
    private var activeEnrollmentSettled = false

    @ObservationIgnored
    private var pendingReconciliation: RunnerAgentSnapshot?

    private var enrollmentLocked = false
    private var hasUnresolvedOutcome = false
    private var awaitingUnenrolledSnapshot = false

    var isBusy: Bool {
        state.isInProgress
    }

    var canBeginEnrollment: Bool {
        activeEnrollment == nil && !enrollmentLocked && !hasUnresolvedOutcome
            && !awaitingUnenrolledSnapshot
    }

    var isSignedIn: Bool {
        authentication.isSignedIn
    }

    var errorMessage: String? {
        switch state {
        case .requiresSignIn:
            "Sign in to ArcBox before connecting this Mac."
        case .failed(let failure):
            failure.localizedDescription
        case .idle, .preparingAgent, .requestingEnrollmentToken, .enrolling,
            .reconcilingEnrollment, .attaching, .ready:
            nil
        }
    }

    @ObservationIgnored
    private let authentication: any RunnerAuthenticationChecking

    @ObservationIgnored
    private let agentReadiness: any RunnerAgentReadying

    @ObservationIgnored
    private let tokenIssuer: (any RunnerEnrollmentTokenIssuing)?

    @ObservationIgnored
    private let attachmentTimeout: Duration

    @ObservationIgnored
    private let snapshotBaselineTimeout: Duration

    @ObservationIgnored
    private let sleeper: @Sendable (Duration) async throws -> Void

    init(
        authentication: any RunnerAuthenticationChecking,
        agentReadiness: any RunnerAgentReadying,
        tokenIssuer: (any RunnerEnrollmentTokenIssuing)?,
        snapshotBaselineTimeout: Duration = .seconds(5),
        attachmentTimeout: Duration = .seconds(30),
        sleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.authentication = authentication
        self.agentReadiness = agentReadiness
        self.tokenIssuer = tokenIssuer
        self.snapshotBaselineTimeout = snapshotBaselineTimeout
        self.attachmentTimeout = attachmentTimeout
        self.sleeper = sleeper
    }

    /// Publishes the signed-out state before any Platform request is made.
    func requireSignedIn() -> Bool {
        guard authentication.isSignedIn else {
            state = .requiresSignIn
            return false
        }
        if state == .requiresSignIn {
            state = .idle
        }
        return true
    }

    /// Enroll this Mac into a selected workspace and wait until its Agent is attached.
    @discardableResult
    func enroll(workspaceID: String, controlPlane: String? = nil) async -> Bool {
        await enroll(source: .workspace(workspaceID), controlPlane: controlPlane)
    }

    /// Enroll this Mac with a user-supplied runner enrollment token.
    @discardableResult
    func enroll(token: String, controlPlane: String? = nil) async -> Bool {
        await enroll(source: .token(token), controlPlane: controlPlane)
    }

    private func enroll(source: EnrollmentSource, controlPlane: String?) async -> Bool {
        guard canBeginEnrollment else { return false }

        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return false }
            let result = await self.performEnrollment(
                source: source,
                controlPlane: controlPlane
            )
            self.markEnrollmentSettled(id: id)
            return result
        }
        activeEnrollment = ActiveEnrollment(id: id, task: task)
        canCancelActiveEnrollment = true
        activeEnrollmentSettled = false
        pendingReconciliation = nil

        // The app-scoped coordinator owns this operation. Caller cancellation
        // (for example, closing a window) must not cancel a post-handoff RPC.
        let succeeded = await task.value

        var reconciledResult: Bool?
        if activeEnrollment?.id == id {
            activeEnrollment = nil
            canCancelActiveEnrollment = false
            reconciledResult = applyPendingReconciliation()
        }
        return reconciledResult ?? succeeded
    }

    /// Cancels the app-owned enrollment operation without stopping the Agent.
    func cancel() {
        guard canCancelActiveEnrollment else { return }
        activeEnrollment?.task.cancel()
    }

    /// Reconciles app-wide Agent snapshots after an enrollment attempt ends.
    ///
    /// An empty host ID never proves a post-handoff failure or explicit
    /// unenrollment. A non-empty ID is positive evidence that the Agent
    /// persisted its credential.
    func reconcile(_ snapshot: RunnerAgentSnapshot) {
        if awaitingUnenrolledSnapshot {
            guard snapshot.enrollment == .unenrolled,
                Self.normalizedHostID(snapshot.hostID) == nil
            else { return }

            awaitingUnenrolledSnapshot = false
            pendingReconciliation = nil
            state = .idle
            return
        }

        switch snapshot.enrollment {
        case .unenrolled:
            return
        case .unspecified, .unrecognized:
            return
        case .attaching, .attached, .updating, .credentialRejected, .detached:
            break
        }

        guard let hostID = Self.normalizedHostID(snapshot.hostID) else { return }
        guard activeEnrollment == nil else {
            pendingReconciliation = snapshot
            return
        }
        applyReconciliation(snapshot, hostID: hostID)
    }

    /// Releases the retry lock only after an explicit Unenroll RPC succeeds.
    func confirmUnenrolled() {
        guard activeEnrollment == nil else { return }
        pendingReconciliation = nil
        hasUnresolvedOutcome = false
        enrollmentLocked = false
        awaitingUnenrolledSnapshot = true
        state = .idle
    }

    /// Gives a pre-handoff cancellation or post-handoff reconciliation a
    /// bounded chance to settle before Desktop closes its client transport.
    func settleForTermination(gracePeriod: Duration) async -> Bool {
        cancel()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracePeriod)
        while !isSettledForTermination, clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                break
            }
        }
        return isSettledForTermination
    }

    private func performEnrollment(source: EnrollmentSource, controlPlane: String?) async -> Bool {
        guard !Task.isCancelled else {
            return fail(.cancelled(hostID: nil))
        }

        guard let source = normalizedEnrollmentSource(source) else { return false }

        state = .preparingAgent
        let agent: any RunnerAgentEnrollmentControlling
        do {
            agent = try await agentReadiness.ensureReady()
            try Task.checkCancellation()
        } catch is CancellationError {
            return fail(.cancelled(hostID: nil))
        } catch {
            return fail(.agentPreparationFailed(message: error.localizedDescription))
        }

        // Watch begins with a full current snapshot. Consume that first value
        // before obtaining or handing off a token, then keep the same buffered
        // stream for post-handoff reconciliation.
        let snapshots = agent.watchSnapshots()
        do {
            let baseline = try await firstSnapshot(in: snapshots)
            try Task.checkCancellation()
            guard acceptEnrollmentBaseline(baseline) else { return false }
        } catch is CancellationError {
            return fail(.cancelled(hostID: nil))
        } catch {
            return fail(.agentPreparationFailed(message: error.localizedDescription))
        }

        guard let enrollmentToken = await enrollmentToken(from: source) else { return false }

        // Another local client may have enrolled while this attempt was being
        // prepared. Positive Agent evidence must stop this non-idempotent handoff;
        // the Agent's enrollment admission gate remains the atomic authority.
        if let reconciledResult = applyPendingBeforeHandoff() {
            return reconciledResult
        }

        state = .enrolling
        // Enroll is not idempotent. From this point onward, cancellation and
        // transport errors cannot prove whether the Agent persisted a credential.
        canCancelActiveEnrollment = false
        enrollmentLocked = true

        let hostID: String
        do {
            let returnedHostID = try await agent.enroll(
                token: enrollmentToken,
                controlPlane: Self.normalizedControlPlane(controlPlane)
            )
            guard let normalizedHostID = Self.normalizedHostID(returnedHostID) else {
                return await reconcileUnknownOutcome(snapshots: snapshots)
            }
            hostID = normalizedHostID
        } catch is CancellationError {
            return await reconcileUnknownOutcome(snapshots: snapshots)
        } catch {
            return await reconcileUnknownOutcome(snapshots: snapshots)
        }

        state = .attaching(hostID: hostID)
        do {
            let attachedHostID = try await waitUntilAttached(
                snapshots: snapshots,
                expectedHostID: hostID
            )
            state = .ready(hostID: attachedHostID)
            return true
        } catch is CancellationError {
            return fail(.cancelled(hostID: hostID))
        } catch let failure as Failure {
            return fail(failure)
        } catch {
            return fail(.stateStreamFailed(hostID: hostID))
        }
    }

    private func normalizedEnrollmentSource(_ source: EnrollmentSource) -> EnrollmentSource? {
        switch source {
        case .workspace(let workspaceID):
            guard requireSignedIn() else { return nil }
            let workspaceID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !workspaceID.isEmpty else {
                _ = fail(.workspaceRequired)
                return nil
            }
            return .workspace(workspaceID)
        case .token(let token):
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                _ = fail(.enrollmentTokenRequired)
                return nil
            }
            return .token(token)
        }
    }

    private func enrollmentToken(from source: EnrollmentSource) async -> String? {
        switch source {
        case .token(let token):
            return token
        case .workspace(let workspaceID):
            guard let tokenIssuer else {
                _ = fail(
                    .enrollmentTokenRequestFailed(
                        message: "Platform client is unavailable."
                    ))
                return nil
            }

            state = .requestingEnrollmentToken
            do {
                let enrollment = try await tokenIssuer.createEnrollmentToken(
                    workspaceID: workspaceID
                )
                try Task.checkCancellation()
                return enrollment.token
            } catch is CancellationError {
                _ = fail(.cancelled(hostID: nil))
            } catch {
                _ = fail(
                    .enrollmentTokenRequestFailed(
                        message: PlatformClient.userMessage(for: error)
                    ))
            }
            return nil
        }
    }

    private func reconcileUnknownOutcome(
        snapshots: AsyncThrowingStream<RunnerAgentSnapshot, Error>
    ) async -> Bool {
        hasUnresolvedOutcome = true
        state = .reconcilingEnrollment

        do {
            let hostID = try await waitUntilAttached(
                snapshots: snapshots,
                expectedHostID: nil
            )
            hasUnresolvedOutcome = false
            state = .ready(hostID: hostID)
            return true
        } catch let failure as Failure {
            if failure.hasHostID {
                hasUnresolvedOutcome = false
                return fail(failure)
            }
            return fail(.enrollmentOutcomeUnknown)
        } catch {
            return fail(.enrollmentOutcomeUnknown)
        }
    }

    private func waitUntilAttached(
        snapshots: AsyncThrowingStream<RunnerAgentSnapshot, Error>,
        expectedHostID: String?
    ) async throws -> String {
        let observation = EnrollmentObservation(hostID: expectedHostID)
        let timeout = attachmentTimeout
        let sleeper = sleeper

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    for try await snapshot in snapshots {
                        guard
                            let hostID = Self.normalizedHostID(snapshot.hostID),
                            await observation.accept(hostID)
                        else { continue }

                        switch snapshot.enrollment {
                        case .attached:
                            return hostID
                        case .credentialRejected:
                            throw Failure.credentialRejected(hostID: hostID)
                        case .detached:
                            throw Failure.detached(hostID: hostID)
                        case .unspecified, .unenrolled, .attaching, .updating, .unrecognized:
                            continue
                        }
                    }
                    if let hostID = await observation.hostID {
                        throw Failure.stateStreamEnded(hostID: hostID)
                    }
                    throw Failure.enrollmentOutcomeUnknown
                } catch is CancellationError {
                    throw CancellationError()
                } catch let failure as Failure {
                    throw failure
                } catch {
                    if let hostID = await observation.hostID {
                        throw Failure.stateStreamFailed(hostID: hostID)
                    }
                    throw Failure.enrollmentOutcomeUnknown
                }
            }

            group.addTask {
                try await sleeper(timeout)
                try Task.checkCancellation()
                if let hostID = await observation.hostID {
                    throw Failure.attachmentTimedOut(hostID: hostID)
                }
                throw Failure.enrollmentOutcomeUnknown
            }

            defer { group.cancelAll() }
            guard let hostID = try await group.next() else {
                throw Failure.enrollmentOutcomeUnknown
            }
            return hostID
        }
    }

    private func fail(_ failure: Failure) -> Bool {
        state = .failed(failure)
        return false
    }

    private var isSettledForTermination: Bool {
        (activeEnrollment == nil || activeEnrollmentSettled) && !hasUnresolvedOutcome
            && pendingReconciliation == nil
    }

    private func firstSnapshot(
        in snapshots: AsyncThrowingStream<RunnerAgentSnapshot, Error>
    ) async throws -> RunnerAgentSnapshot {
        let timeout = snapshotBaselineTimeout

        return try await withThrowingTaskGroup(of: RunnerAgentSnapshot.self) { group in
            group.addTask {
                var iterator = snapshots.makeAsyncIterator()
                guard let snapshot = try await iterator.next() else {
                    throw SnapshotBaselineError.streamEnded
                }
                return snapshot
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw SnapshotBaselineError.timedOut
            }

            defer { group.cancelAll() }
            guard let snapshot = try await group.next() else {
                throw SnapshotBaselineError.streamEnded
            }
            return snapshot
        }
    }

    private func acceptEnrollmentBaseline(_ snapshot: RunnerAgentSnapshot) -> Bool {
        let hostID = Self.normalizedHostID(snapshot.hostID)
        switch snapshot.enrollment {
        case .unenrolled where hostID == nil:
            return true
        case .attaching, .updating:
            guard let hostID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .attaching(hostID: hostID)
        case .attached:
            guard let hostID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .ready(hostID: hostID)
        case .detached:
            guard let hostID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .failed(.detached(hostID: hostID))
        case .credentialRejected:
            guard let hostID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .failed(.credentialRejected(hostID: hostID))
        case .unenrolled:
            return failUnknownOutcome()
        case .unspecified, .unrecognized:
            if hostID != nil {
                return failUnknownOutcome()
            }
            return fail(
                .agentPreparationFailed(
                    message: "Runner Agent returned an invalid enrollment state."
                ))
        }
        return false
    }

    private func failUnknownOutcome() -> Bool {
        hasUnresolvedOutcome = true
        enrollmentLocked = true
        return fail(.enrollmentOutcomeUnknown)
    }

    private func applyPendingReconciliation() -> Bool? {
        guard let snapshot = pendingReconciliation else { return nil }
        pendingReconciliation = nil

        // Independent Watch streams have no shared sequence. Preserve a known
        // terminal state, and let a queued terminal state conservatively win
        // over ready rather than reporting a potentially revoked credential.
        switch state {
        case .ready where !snapshot.enrollment.isTerminal:
            return nil
        case .failed(.credentialRejected), .failed(.detached):
            return nil
        default:
            break
        }

        guard let hostID = Self.normalizedHostID(snapshot.hostID) else { return nil }
        applyReconciliation(snapshot, hostID: hostID)
        if case .ready = state { return true }
        return false
    }

    private func applyPendingBeforeHandoff() -> Bool? {
        guard let snapshot = pendingReconciliation else { return nil }
        pendingReconciliation = nil
        guard let hostID = Self.normalizedHostID(snapshot.hostID) else { return nil }

        applyReconciliation(snapshot, hostID: hostID)
        if case .ready = state { return true }
        return false
    }

    private func applyReconciliation(
        _ snapshot: RunnerAgentSnapshot,
        hostID: String
    ) {
        hasUnresolvedOutcome = false
        enrollmentLocked = true

        switch snapshot.enrollment {
        case .attaching, .updating:
            state = .attaching(hostID: hostID)
        case .attached:
            state = .ready(hostID: hostID)
        case .credentialRejected:
            state = .failed(.credentialRejected(hostID: hostID))
        case .detached:
            state = .failed(.detached(hostID: hostID))
        case .unenrolled, .unspecified, .unrecognized:
            break
        }
    }

    private func markEnrollmentSettled(id: UUID) {
        guard activeEnrollment?.id == id else { return }
        activeEnrollmentSettled = true
    }

    nonisolated private static func normalizedControlPlane(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    nonisolated private static func normalizedHostID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

extension RunnerEnrollmentState {
    fileprivate var isTerminal: Bool {
        switch self {
        case .credentialRejected, .detached:
            true
        case .unenrolled, .attaching, .attached, .updating, .unspecified, .unrecognized:
            false
        }
    }
}

private actor EnrollmentObservation {
    private(set) var hostID: String?

    init(hostID: String?) {
        self.hostID = hostID
    }

    func accept(_ candidate: String) -> Bool {
        if let hostID {
            return candidate == hostID
        }
        hostID = candidate
        return true
    }
}

extension RunnerEnrollmentCoordinator.Failure {
    fileprivate var hasHostID: Bool {
        switch self {
        case .credentialRejected, .detached, .stateStreamEnded, .stateStreamFailed,
            .attachmentTimedOut, .cancelled(hostID: .some):
            true
        case .workspaceRequired, .enrollmentTokenRequired, .agentPreparationFailed,
            .enrollmentTokenRequestFailed,
            .enrollmentOutcomeUnknown, .cancelled(hostID: nil):
            false
        }
    }
}

extension RunnerEnrollmentCoordinator.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .workspaceRequired:
            "An ArcBox workspace is required for enrollment."
        case .enrollmentTokenRequired:
            "A runner enrollment token is required."
        case .agentPreparationFailed(let message):
            message
        case .enrollmentTokenRequestFailed(let message):
            message
        case .enrollmentOutcomeUnknown:
            "The enrollment result is unknown. ArcBox will keep reconciling the Runner Agent state."
        case .credentialRejected:
            "The runner gateway rejected this Mac's credential."
        case .detached:
            "This Mac is enrolled, but runner participation is disabled."
        case .stateStreamEnded:
            "The Runner Agent stopped reporting enrollment state."
        case .stateStreamFailed:
            "The Runner Agent enrollment state could not be observed."
        case .attachmentTimedOut:
            "This Mac enrolled, but did not attach to the runner gateway in time."
        case .cancelled:
            "Runner enrollment was cancelled."
        }
    }
}
