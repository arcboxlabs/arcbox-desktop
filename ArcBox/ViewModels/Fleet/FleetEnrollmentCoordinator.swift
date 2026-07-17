import ArcBoxAuth
import FleetControlClient
import FleetPlatformClient
import Foundation
import Observation

@MainActor
protocol FleetAuthenticationChecking: Sendable {
    var isSignedIn: Bool { get }
}

extension AuthSession: FleetAuthenticationChecking {
    var isSignedIn: Bool {
        status == .signedIn
    }
}

@MainActor
protocol FleetEnrollmentTokenIssuing: Sendable {
    func createEnrollmentToken(workspaceID: String) async throws -> FleetEnrollmentToken
}

extension FleetPlatformClient: FleetEnrollmentTokenIssuing {}

@MainActor
protocol FleetAgentEnrollmentControlling: Sendable {
    func enroll(token: String, controlPlane: String?) async throws -> String
    func watchSnapshots() -> AsyncThrowingStream<FleetAgentSnapshot, Error>
}

extension FleetControlClient: FleetAgentEnrollmentControlling {}

@MainActor
protocol FleetAgentReadying: Sendable {
    func ensureReady() async throws -> any FleetAgentEnrollmentControlling
}

/// Coordinates Platform-issued and manually supplied Agent enrollment handoffs.
@MainActor
@Observable
final class FleetEnrollmentCoordinator {
    enum State: Equatable, Sendable {
        case idle
        case requiresSignIn
        case preparingAgent
        case requestingEnrollmentToken
        case enrolling
        case reconcilingEnrollment
        case attaching(machineID: String)
        case ready(machineID: String)
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
        case credentialRejected(machineID: String)
        case detached(machineID: String)
        case stateStreamEnded(machineID: String)
        case stateStreamFailed(machineID: String)
        case attachmentTimedOut(machineID: String)
        case cancelled(machineID: String?)
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
                "Fleet Agent stopped reporting state before its initial snapshot."
            case .timedOut:
                "Fleet Agent did not report its initial state in time."
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
    private var pendingReconciliation: FleetAgentSnapshot?

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
    private let authentication: any FleetAuthenticationChecking

    @ObservationIgnored
    private let agentReadiness: any FleetAgentReadying

    @ObservationIgnored
    private let tokenIssuer: (any FleetEnrollmentTokenIssuing)?

    @ObservationIgnored
    private let attachmentTimeout: Duration

    @ObservationIgnored
    private let snapshotBaselineTimeout: Duration

    @ObservationIgnored
    private let sleeper: @Sendable (Duration) async throws -> Void

    init(
        authentication: any FleetAuthenticationChecking,
        agentReadiness: any FleetAgentReadying,
        tokenIssuer: (any FleetEnrollmentTokenIssuing)?,
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

    /// Enroll this Mac with a user-supplied Fleet enrollment token.
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
    /// An empty machine ID never proves a post-handoff failure or explicit
    /// unenrollment. A non-empty ID is positive evidence that the Agent
    /// persisted its credential.
    func reconcile(_ snapshot: FleetAgentSnapshot) {
        if awaitingUnenrolledSnapshot {
            guard snapshot.enrollment == .unenrolled,
                Self.normalizedMachineID(snapshot.machineID) == nil
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

        guard let machineID = Self.normalizedMachineID(snapshot.machineID) else { return }
        guard activeEnrollment == nil else {
            pendingReconciliation = snapshot
            return
        }
        applyReconciliation(snapshot, machineID: machineID)
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
            return fail(.cancelled(machineID: nil))
        }

        guard let source = normalizedEnrollmentSource(source) else { return false }

        state = .preparingAgent
        let agent: any FleetAgentEnrollmentControlling
        do {
            agent = try await agentReadiness.ensureReady()
            try Task.checkCancellation()
        } catch is CancellationError {
            return fail(.cancelled(machineID: nil))
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
            return fail(.cancelled(machineID: nil))
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

        let machineID: String
        do {
            let returnedMachineID = try await agent.enroll(
                token: enrollmentToken,
                controlPlane: Self.normalizedControlPlane(controlPlane)
            )
            guard let normalizedMachineID = Self.normalizedMachineID(returnedMachineID) else {
                return await reconcileUnknownOutcome(snapshots: snapshots)
            }
            machineID = normalizedMachineID
        } catch is CancellationError {
            return await reconcileUnknownOutcome(snapshots: snapshots)
        } catch {
            return await reconcileUnknownOutcome(snapshots: snapshots)
        }

        state = .attaching(machineID: machineID)
        do {
            let attachedMachineID = try await waitUntilAttached(
                snapshots: snapshots,
                expectedMachineID: machineID
            )
            state = .ready(machineID: attachedMachineID)
            return true
        } catch is CancellationError {
            return fail(.cancelled(machineID: machineID))
        } catch let failure as Failure {
            return fail(failure)
        } catch {
            return fail(.stateStreamFailed(machineID: machineID))
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
                        message: "Fleet Platform client is unavailable."
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
                _ = fail(.cancelled(machineID: nil))
            } catch {
                _ = fail(
                    .enrollmentTokenRequestFailed(
                        message: FleetPlatformClient.userMessage(for: error)
                    ))
            }
            return nil
        }
    }

    private func reconcileUnknownOutcome(
        snapshots: AsyncThrowingStream<FleetAgentSnapshot, Error>
    ) async -> Bool {
        hasUnresolvedOutcome = true
        state = .reconcilingEnrollment

        do {
            let machineID = try await waitUntilAttached(
                snapshots: snapshots,
                expectedMachineID: nil
            )
            hasUnresolvedOutcome = false
            state = .ready(machineID: machineID)
            return true
        } catch let failure as Failure {
            if failure.hasMachineID {
                hasUnresolvedOutcome = false
                return fail(failure)
            }
            return fail(.enrollmentOutcomeUnknown)
        } catch {
            return fail(.enrollmentOutcomeUnknown)
        }
    }

    private func waitUntilAttached(
        snapshots: AsyncThrowingStream<FleetAgentSnapshot, Error>,
        expectedMachineID: String?
    ) async throws -> String {
        let observation = EnrollmentObservation(machineID: expectedMachineID)
        let timeout = attachmentTimeout
        let sleeper = sleeper

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    for try await snapshot in snapshots {
                        guard
                            let machineID = Self.normalizedMachineID(snapshot.machineID),
                            await observation.accept(machineID)
                        else { continue }

                        switch snapshot.enrollment {
                        case .attached:
                            return machineID
                        case .credentialRejected:
                            throw Failure.credentialRejected(machineID: machineID)
                        case .detached:
                            throw Failure.detached(machineID: machineID)
                        case .unspecified, .unenrolled, .attaching, .updating, .unrecognized:
                            continue
                        }
                    }
                    if let machineID = await observation.machineID {
                        throw Failure.stateStreamEnded(machineID: machineID)
                    }
                    throw Failure.enrollmentOutcomeUnknown
                } catch is CancellationError {
                    throw CancellationError()
                } catch let failure as Failure {
                    throw failure
                } catch {
                    if let machineID = await observation.machineID {
                        throw Failure.stateStreamFailed(machineID: machineID)
                    }
                    throw Failure.enrollmentOutcomeUnknown
                }
            }

            group.addTask {
                try await sleeper(timeout)
                try Task.checkCancellation()
                if let machineID = await observation.machineID {
                    throw Failure.attachmentTimedOut(machineID: machineID)
                }
                throw Failure.enrollmentOutcomeUnknown
            }

            defer { group.cancelAll() }
            guard let machineID = try await group.next() else {
                throw Failure.enrollmentOutcomeUnknown
            }
            return machineID
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
        in snapshots: AsyncThrowingStream<FleetAgentSnapshot, Error>
    ) async throws -> FleetAgentSnapshot {
        let timeout = snapshotBaselineTimeout

        return try await withThrowingTaskGroup(of: FleetAgentSnapshot.self) { group in
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

    private func acceptEnrollmentBaseline(_ snapshot: FleetAgentSnapshot) -> Bool {
        let machineID = Self.normalizedMachineID(snapshot.machineID)
        switch snapshot.enrollment {
        case .unenrolled where machineID == nil:
            return true
        case .attaching, .updating:
            guard let machineID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .attaching(machineID: machineID)
        case .attached:
            guard let machineID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .ready(machineID: machineID)
        case .detached:
            guard let machineID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .failed(.detached(machineID: machineID))
        case .credentialRejected:
            guard let machineID else { return failUnknownOutcome() }
            enrollmentLocked = true
            state = .failed(.credentialRejected(machineID: machineID))
        case .unenrolled:
            return failUnknownOutcome()
        case .unspecified, .unrecognized:
            if machineID != nil {
                return failUnknownOutcome()
            }
            return fail(
                .agentPreparationFailed(
                    message: "Fleet Agent returned an invalid enrollment state."
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

        guard let machineID = Self.normalizedMachineID(snapshot.machineID) else { return nil }
        applyReconciliation(snapshot, machineID: machineID)
        if case .ready = state { return true }
        return false
    }

    private func applyPendingBeforeHandoff() -> Bool? {
        guard let snapshot = pendingReconciliation else { return nil }
        pendingReconciliation = nil
        guard let machineID = Self.normalizedMachineID(snapshot.machineID) else { return nil }

        applyReconciliation(snapshot, machineID: machineID)
        if case .ready = state { return true }
        return false
    }

    private func applyReconciliation(
        _ snapshot: FleetAgentSnapshot,
        machineID: String
    ) {
        hasUnresolvedOutcome = false
        enrollmentLocked = true

        switch snapshot.enrollment {
        case .attaching, .updating:
            state = .attaching(machineID: machineID)
        case .attached:
            state = .ready(machineID: machineID)
        case .credentialRejected:
            state = .failed(.credentialRejected(machineID: machineID))
        case .detached:
            state = .failed(.detached(machineID: machineID))
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

    nonisolated private static func normalizedMachineID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

extension FleetEnrollmentState {
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
    private(set) var machineID: String?

    init(machineID: String?) {
        self.machineID = machineID
    }

    func accept(_ candidate: String) -> Bool {
        if let machineID {
            return candidate == machineID
        }
        machineID = candidate
        return true
    }
}

extension FleetEnrollmentCoordinator.Failure {
    fileprivate var hasMachineID: Bool {
        switch self {
        case .credentialRejected, .detached, .stateStreamEnded, .stateStreamFailed,
            .attachmentTimedOut, .cancelled(machineID: .some):
            true
        case .workspaceRequired, .enrollmentTokenRequired, .agentPreparationFailed,
            .enrollmentTokenRequestFailed,
            .enrollmentOutcomeUnknown, .cancelled(machineID: nil):
            false
        }
    }
}

extension FleetEnrollmentCoordinator.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .workspaceRequired:
            "An ArcBox workspace is required for enrollment."
        case .enrollmentTokenRequired:
            "A Fleet enrollment token is required."
        case .agentPreparationFailed(let message):
            message
        case .enrollmentTokenRequestFailed(let message):
            message
        case .enrollmentOutcomeUnknown:
            "The enrollment result is unknown. ArcBox will keep reconciling the Fleet Agent state."
        case .credentialRejected:
            "The Fleet gateway rejected this Mac's credential."
        case .detached:
            "This Mac is enrolled, but Fleet participation is disabled."
        case .stateStreamEnded:
            "The Fleet Agent stopped reporting enrollment state."
        case .stateStreamFailed:
            "The Fleet Agent enrollment state could not be observed."
        case .attachmentTimedOut:
            "This Mac enrolled, but did not attach to the Fleet gateway in time."
        case .cancelled:
            "Fleet enrollment was cancelled."
        }
    }
}
