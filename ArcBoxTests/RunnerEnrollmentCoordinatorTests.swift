import PlatformClient
import RunnerAgentClient
import XCTest

@testable import ArcBox

@MainActor
final class RunnerEnrollmentCoordinatorTests: XCTestCase {
    func testHappyPathCreatesOneTokenBeforeLocalEnrollAndWaitsForAttached() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .success("rhost_123"),
            snapshots: [
                snapshot(.updating, hostID: "rhost_123"),
                snapshot(.attaching, hostID: "rhost_123"),
                snapshot(.attached, hostID: "rhost_123"),
            ]
        )
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_123"))
        XCTAssertEqual(calls.entries, ["ensureReady", "watch", "token", "enroll"])
        XCTAssertEqual(tokenIssuer.requestedWorkspaceIDs, ["ws_123"])
        XCTAssertEqual(agent.receivedTokens, ["flet_test_secret"])
    }

    func testEnrollmentWaitsForInitialWatchSnapshotBeforeRequestingToken() async {
        let calls = CallRecorder()
        let baselineGate = AsyncGate()
        let agent = AgentStub(
            calls: calls,
            snapshots: [snapshot(.attached, hostID: "rhost_123")],
            baselineGate: baselineGate
        )
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )
        let enrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ calls.entries == ["ensureReady", "watch"] }) else {
            XCTFail("Enrollment did not open the Agent state stream.")
            await baselineGate.open()
            _ = await enrollment.value
            return
        }

        XCTAssertTrue(tokenIssuer.requestedWorkspaceIDs.isEmpty)
        await baselineGate.open()
        let succeeded = await enrollment.value

        XCTAssertTrue(succeeded)
        XCTAssertEqual(calls.entries, ["ensureReady", "watch", "token", "enroll"])
    }

    func testSignedOutRequiresSignInWithoutCallingDependencies() async {
        let calls = CallRecorder()
        let agent = AgentStub(calls: calls)
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer,
            isSignedIn: false
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(coordinator.state, .requiresSignIn)
        XCTAssertTrue(calls.entries.isEmpty)
    }

    func testManualTokenEnrollmentWorksSignedOutWithoutPlatformTokenIssuer() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .success("rhost_manual"),
            snapshots: [snapshot(.attached, hostID: "rhost_manual")]
        )
        let coordinator = RunnerEnrollmentCoordinator(
            authentication: AuthenticationStub(isSignedIn: false),
            agentReadiness: AgentReadinessStub(calls: calls, agent: agent),
            tokenIssuer: nil,
            sleeper: waitForCancellation
        )

        let succeeded = await coordinator.enroll(token: "  flet_manual_secret\n")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_manual"))
        XCTAssertEqual(calls.entries, ["ensureReady", "watch", "enroll"])
        XCTAssertEqual(agent.receivedTokens, ["flet_manual_secret"])
    }

    func testManualTokenEnrollmentRejectsEmptyInputBeforeCallingAgent() async {
        let calls = CallRecorder()
        let agent = AgentStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            isSignedIn: false
        )

        let succeeded = await coordinator.enroll(token: " \n ")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(coordinator.state, .failed(.enrollmentTokenRequired))
        XCTAssertTrue(calls.entries.isEmpty)
        XCTAssertTrue(agent.receivedTokens.isEmpty)
    }

    func testTokenFailureDoesNotCallAgent() async {
        let calls = CallRecorder()
        let agent = AgentStub(calls: calls)
        let tokenIssuer = TokenIssuerStub(calls: calls, result: .failure(.expected))
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            coordinator.state,
            .failed(.enrollmentTokenRequestFailed(message: "Expected test failure."))
        )
        XCTAssertEqual(calls.entries, ["ensureReady", "watch", "token"])
        XCTAssertTrue(agent.receivedTokens.isEmpty)
    }

    func testReadinessFailureStopsBeforeTokenRequest() async {
        let calls = CallRecorder()
        let agent = AgentStub(calls: calls)
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer,
            readinessFailure: .expected
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            coordinator.state,
            .failed(.agentPreparationFailed(message: "Expected test failure."))
        )
        XCTAssertEqual(calls.entries, ["ensureReady"])
        XCTAssertTrue(tokenIssuer.requestedWorkspaceIDs.isEmpty)
        XCTAssertTrue(agent.receivedTokens.isEmpty)
    }

    func testLocalEnrollFailureIsUnknownAndDoesNotRetainToken() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .failure(.expected)
        )
        let coordinator = makeCoordinator(calls: calls, agent: agent)

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(coordinator.state, .failed(.enrollmentOutcomeUnknown))
        XCTAssertEqual(calls.entries, ["ensureReady", "watch", "token", "enroll"])
        XCTAssertFalse(String(describing: coordinator.state).contains("flet_test_secret"))

        coordinator.reconcile(snapshot(.unenrolled, hostID: nil))
        XCTAssertEqual(coordinator.state, .failed(.enrollmentOutcomeUnknown))
        XCTAssertFalse(coordinator.canBeginEnrollment)

        coordinator.reconcile(snapshot(.attached, hostID: "rhost_reconciled"))
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_reconciled"))

        let retrySucceeded = await coordinator.enroll(workspaceID: "ws_retry")

        XCTAssertFalse(retrySucceeded)
        XCTAssertEqual(tokenIssuerCallCount(in: calls.entries), 1)
        XCTAssertEqual(agent.receivedTokens.count, 1)
        XCTAssertFalse(coordinator.canBeginEnrollment)
    }

    func testAlreadyEnrolledBaselineDoesNotRequestToken() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            baseline: snapshot(.attached, hostID: "rhost_existing")
        )
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_existing"))
        XCTAssertEqual(calls.entries, ["ensureReady", "watch"])
        XCTAssertTrue(tokenIssuer.requestedWorkspaceIDs.isEmpty)
        XCTAssertTrue(agent.receivedTokens.isEmpty)
        XCTAssertFalse(coordinator.canBeginEnrollment)

        coordinator.reconcile(snapshot(.unenrolled, hostID: nil))
        let retrySucceeded = await coordinator.enroll(workspaceID: "ws_retry")

        XCTAssertFalse(retrySucceeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_existing"))
        XCTAssertTrue(tokenIssuer.requestedWorkspaceIDs.isEmpty)

        coordinator.confirmUnenrolled()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(coordinator.canBeginEnrollment)

        coordinator.reconcile(snapshot(.attached, hostID: "rhost_existing"))

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertFalse(coordinator.canBeginEnrollment)

        coordinator.reconcile(snapshot(.unenrolled, hostID: nil))

        XCTAssertTrue(coordinator.canBeginEnrollment)
    }

    func testLocalEnrollErrorReconcilesAttachedSnapshotWithoutRetry() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .failure(.expected),
            snapshots: [snapshot(.attached, hostID: "rhost_reconciled")]
        )
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_reconciled"))
        XCTAssertEqual(tokenIssuer.requestedWorkspaceIDs.count, 1)
        XCTAssertEqual(agent.receivedTokens.count, 1)
        XCTAssertFalse(coordinator.canBeginEnrollment)

        let retrySucceeded = await coordinator.enroll(workspaceID: "ws_retry")

        XCTAssertFalse(retrySucceeded)
        XCTAssertEqual(tokenIssuer.requestedWorkspaceIDs.count, 1)
        XCTAssertFalse(coordinator.canBeginEnrollment)
    }

    func testUpdatingBaselineDoesNotRequestTokenAndConvergesThroughReconciliation() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            baseline: snapshot(.updating, hostID: "rhost_existing")
        )
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(coordinator.state, .attaching(hostID: "rhost_existing"))
        XCTAssertEqual(calls.entries, ["ensureReady", "watch"])
        XCTAssertTrue(tokenIssuer.requestedWorkspaceIDs.isEmpty)
        XCTAssertTrue(agent.receivedTokens.isEmpty)
        XCTAssertFalse(coordinator.canBeginEnrollment)

        coordinator.reconcile(snapshot(.attached, hostID: "rhost_existing"))

        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_existing"))
    }

    func testGlobalAttachedSnapshotDuringActiveAttemptIsAppliedAfterInternalUnknown() async {
        let calls = CallRecorder()
        let enrollGate = AsyncGate()
        let agent = AgentStub(
            calls: calls,
            streamCompletion: .stayOpen,
            enrollOperation: {
                await enrollGate.wait()
                throw TestFailure.expected
            }
        )
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer,
            sleeper: { _ in }
        )
        let enrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ agent.receivedTokens.count == 1 }) else {
            XCTFail("Enrollment did not hand the token to the Agent.")
            await enrollGate.open()
            _ = await enrollment.value
            return
        }

        coordinator.reconcile(snapshot(.attached, hostID: "rhost_global"))
        XCTAssertEqual(coordinator.state, .enrolling)
        await enrollGate.open()
        let succeeded = await enrollment.value

        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_global"))
        XCTAssertFalse(coordinator.canBeginEnrollment)
        XCTAssertEqual(tokenIssuer.requestedWorkspaceIDs.count, 1)
    }

    func testObservedEnrollmentBeforeHandoffPreventsDuplicateLocalEnroll() async {
        let calls = CallRecorder()
        let tokenGate = AsyncGate()
        let agent = AgentStub(calls: calls)
        let tokenIssuer = TokenIssuerStub(
            calls: calls,
            operation: { await tokenGate.wait() }
        )
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )
        let enrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ tokenIssuer.requestedWorkspaceIDs.count == 1 }) else {
            XCTFail("Enrollment did not request its token.")
            await tokenGate.open()
            _ = await enrollment.value
            return
        }

        coordinator.reconcile(snapshot(.attached, hostID: "rhost_external"))
        await tokenGate.open()
        let succeeded = await enrollment.value

        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_external"))
        XCTAssertTrue(agent.receivedTokens.isEmpty)
        XCTAssertFalse(coordinator.canBeginEnrollment)
    }

    func testQueuedAttachedSnapshotDoesNotOverwriteNewerInternalTerminalState() async {
        let calls = CallRecorder()
        let enrollGate = AsyncGate()
        let agent = AgentStub(
            calls: calls,
            snapshots: [snapshot(.credentialRejected, hostID: "rhost_123")],
            enrollOperation: { await enrollGate.wait() }
        )
        let coordinator = makeCoordinator(calls: calls, agent: agent)
        let enrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ agent.receivedTokens.count == 1 }) else {
            XCTFail("Enrollment did not hand the token to the Agent.")
            await enrollGate.open()
            _ = await enrollment.value
            return
        }

        coordinator.reconcile(snapshot(.attached, hostID: "rhost_123"))
        await enrollGate.open()
        let succeeded = await enrollment.value

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            coordinator.state,
            .failed(.credentialRejected(hostID: "rhost_123"))
        )
        XCTAssertFalse(coordinator.canBeginEnrollment)
    }

    func testQueuedTerminalSnapshotOverridesInternalReadyState() async {
        let calls = CallRecorder()
        let enrollGate = AsyncGate()
        let agent = AgentStub(
            calls: calls,
            snapshots: [snapshot(.attached, hostID: "rhost_123")],
            enrollOperation: { await enrollGate.wait() }
        )
        let coordinator = makeCoordinator(calls: calls, agent: agent)
        let enrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ agent.receivedTokens.count == 1 }) else {
            XCTFail("Enrollment did not hand the token to the Agent.")
            await enrollGate.open()
            _ = await enrollment.value
            return
        }

        coordinator.reconcile(snapshot(.credentialRejected, hostID: "rhost_123"))
        await enrollGate.open()
        let succeeded = await enrollment.value

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            coordinator.state,
            .failed(.credentialRejected(hostID: "rhost_123"))
        )
        XCTAssertFalse(coordinator.canBeginEnrollment)
    }

    func testCredentialRejectedIsTerminalFailure() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .success("rhost_rejected"),
            snapshots: [snapshot(.credentialRejected, hostID: "rhost_rejected")]
        )
        let tokenIssuer = TokenIssuerStub(calls: calls)
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            coordinator.state,
            .failed(.credentialRejected(hostID: "rhost_rejected"))
        )
        XCTAssertEqual(tokenIssuer.requestedWorkspaceIDs.count, 1)
        XCTAssertEqual(agent.receivedTokens.count, 1)
        XCTAssertFalse(coordinator.canBeginEnrollment)

        let retrySucceeded = await coordinator.enroll(workspaceID: "ws_retry")

        XCTAssertFalse(retrySucceeded)
        XCTAssertEqual(tokenIssuer.requestedWorkspaceIDs.count, 1)
    }

    func testAttachmentTimeoutDoesNotSleepInRealTime() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .success("rhost_slow"),
            snapshots: [snapshot(.attaching, hostID: "rhost_slow")],
            streamCompletion: .stayOpen
        )
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            sleeper: { _ in }
        )

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(
            coordinator.state,
            .failed(.attachmentTimedOut(hostID: "rhost_slow"))
        )
        XCTAssertEqual(agent.receivedTokens.count, 1)
        XCTAssertFalse(coordinator.canBeginEnrollment)

        let retrySucceeded = await coordinator.enroll(workspaceID: "ws_retry")

        XCTAssertFalse(retrySucceeded)
        XCTAssertEqual(tokenIssuerCallCount(in: calls.entries), 1)
    }

    func testStaleHostSnapshotIsIgnored() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .success("rhost_current"),
            snapshots: [
                snapshot(.attached, hostID: "rhost_stale"),
                snapshot(.attaching, hostID: "rhost_current"),
                snapshot(.attached, hostID: "rhost_current"),
            ]
        )
        let coordinator = makeCoordinator(calls: calls, agent: agent)

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_current"))
    }

    func testConcurrentEnrollmentDoesNotIssueSecondTokenAndCanBeCancelled() async {
        let calls = CallRecorder()
        let agent = AgentStub(calls: calls)
        let tokenIssuer = TokenIssuerStub(
            calls: calls,
            operation: { try await waitForCancellation(.zero) }
        )
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )
        let firstEnrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ tokenIssuer.requestedWorkspaceIDs.count == 1 }) else {
            XCTFail("The first enrollment did not request its token.")
            coordinator.cancel()
            _ = await firstEnrollment.value
            return
        }

        let secondSucceeded = await coordinator.enroll(workspaceID: "ws_456")
        let settled = await coordinator.settleForTermination(gracePeriod: .seconds(1))
        let firstSucceeded = await firstEnrollment.value

        XCTAssertTrue(settled)
        XCTAssertFalse(firstSucceeded)
        XCTAssertFalse(secondSucceeded)
        XCTAssertEqual(tokenIssuer.requestedWorkspaceIDs, ["ws_123"])
        XCTAssertTrue(agent.receivedTokens.isEmpty)
        XCTAssertEqual(coordinator.state, .failed(.cancelled(hostID: nil)))
    }

    func testCancellationDuringLocalEnrollReportsUnknownOutcome() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollOperation: { throw CancellationError() }
        )
        let coordinator = makeCoordinator(calls: calls, agent: agent)

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(coordinator.state, .failed(.enrollmentOutcomeUnknown))
    }

    func testTerminationDoesNotAbortPostHandoffEnrollAndReportsGraceTimeout() async {
        let calls = CallRecorder()
        let gate = AsyncGate()
        let agent = AgentStub(
            calls: calls,
            snapshots: [snapshot(.attached, hostID: "rhost_123")],
            enrollOperation: { await gate.wait() }
        )
        let coordinator = makeCoordinator(calls: calls, agent: agent)
        let enrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ agent.receivedTokens.count == 1 }) else {
            XCTFail("Enrollment did not hand the token to the Agent.")
            await gate.open()
            _ = await enrollment.value
            return
        }

        let settled = await coordinator.settleForTermination(gracePeriod: .zero)
        await gate.open()
        let succeeded = await enrollment.value

        XCTAssertFalse(settled)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(coordinator.state, .ready(hostID: "rhost_123"))
    }

    func testTerminationDoesNotReportSettledForUnresolvedOutcome() async {
        let calls = CallRecorder()
        let agent = AgentStub(
            calls: calls,
            enrollmentResult: .failure(.expected)
        )
        let coordinator = makeCoordinator(calls: calls, agent: agent)

        let succeeded = await coordinator.enroll(workspaceID: "ws_123")
        let settled = await coordinator.settleForTermination(gracePeriod: .zero)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(settled)
        XCTAssertEqual(coordinator.state, .failed(.enrollmentOutcomeUnknown))
    }

    func testCancellationBeforeHandoffStopsNonCooperativeTokenIssuer() async {
        let calls = CallRecorder()
        let gate = AsyncGate()
        let agent = AgentStub(calls: calls)
        let tokenIssuer = TokenIssuerStub(
            calls: calls,
            operation: { await gate.wait() }
        )
        let coordinator = makeCoordinator(
            calls: calls,
            agent: agent,
            tokenIssuer: tokenIssuer
        )
        let enrollment = Task {
            await coordinator.enroll(workspaceID: "ws_123")
        }
        guard await waitUntil({ tokenIssuer.requestedWorkspaceIDs.count == 1 }) else {
            XCTFail("Enrollment did not request its token.")
            await gate.open()
            _ = await enrollment.value
            return
        }

        coordinator.cancel()
        await gate.open()
        let succeeded = await enrollment.value

        XCTAssertFalse(succeeded)
        XCTAssertEqual(coordinator.state, .failed(.cancelled(hostID: nil)))
        XCTAssertTrue(agent.receivedTokens.isEmpty)
        XCTAssertTrue(coordinator.canBeginEnrollment)
    }

    private func makeCoordinator(
        calls: CallRecorder,
        agent: AgentStub,
        tokenIssuer: TokenIssuerStub? = nil,
        isSignedIn: Bool = true,
        readinessFailure: TestFailure? = nil,
        sleeper: @escaping @Sendable (Duration) async throws -> Void = waitForCancellation
    ) -> RunnerEnrollmentCoordinator {
        RunnerEnrollmentCoordinator(
            authentication: AuthenticationStub(isSignedIn: isSignedIn),
            agentReadiness: AgentReadinessStub(
                calls: calls,
                agent: agent,
                failure: readinessFailure
            ),
            tokenIssuer: tokenIssuer ?? TokenIssuerStub(calls: calls),
            sleeper: sleeper
        )
    }

    private func snapshot(
        _ enrollment: RunnerEnrollmentState,
        hostID: String?
    ) -> RunnerAgentSnapshot {
        RunnerAgentSnapshot(
            enrollment: enrollment,
            hostID: hostID,
            isDraining: false,
            capabilities: [],
            inFlightJobs: [],
            recentVerdicts: [],
            telemetry: nil,
            settings: nil
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }

    private func tokenIssuerCallCount(in entries: [String]) -> Int {
        entries.count(where: { $0 == "token" })
    }
}

@MainActor
private final class AuthenticationStub: RunnerAuthenticationChecking {
    let isSignedIn: Bool

    init(isSignedIn: Bool) {
        self.isSignedIn = isSignedIn
    }
}

@MainActor
private final class CallRecorder {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

@MainActor
private final class TokenIssuerStub: RunnerEnrollmentTokenIssuing {
    private let calls: CallRecorder
    private let result: Result<RunnerEnrollmentToken, TestFailure>
    private let operation: (@MainActor () async throws -> Void)?
    private(set) var requestedWorkspaceIDs: [String] = []

    init(
        calls: CallRecorder,
        result: Result<RunnerEnrollmentToken, TestFailure> = .success(
            RunnerEnrollmentToken(
                token: "flet_test_secret",
                expiresAt: .now.addingTimeInterval(3600)
            )),
        operation: (@MainActor () async throws -> Void)? = nil
    ) {
        self.calls = calls
        self.result = result
        self.operation = operation
    }

    func createEnrollmentToken(workspaceID: String) async throws -> RunnerEnrollmentToken {
        calls.record("token")
        requestedWorkspaceIDs.append(workspaceID)
        try await operation?()
        return try result.get()
    }
}

@MainActor
private final class AgentReadinessStub: RunnerAgentReadying {
    private let calls: CallRecorder
    private let agent: any RunnerAgentEnrollmentControlling
    private let failure: TestFailure?

    init(
        calls: CallRecorder,
        agent: any RunnerAgentEnrollmentControlling,
        failure: TestFailure? = nil
    ) {
        self.calls = calls
        self.agent = agent
        self.failure = failure
    }

    func ensureReady() async throws -> any RunnerAgentEnrollmentControlling {
        calls.record("ensureReady")
        if let failure { throw failure }
        return agent
    }
}

@MainActor
private final class AgentStub: RunnerAgentEnrollmentControlling {
    enum StreamCompletion: Sendable {
        case finish
        case stayOpen
    }

    private let calls: CallRecorder
    private let enrollmentResult: Result<String, TestFailure>
    private let baseline: RunnerAgentSnapshot
    private let snapshots: [RunnerAgentSnapshot]
    private let streamCompletion: StreamCompletion
    private let baselineGate: AsyncGate?
    private let enrollOperation: (@MainActor () async throws -> Void)?
    private(set) var receivedTokens: [String] = []

    init(
        calls: CallRecorder,
        baseline: RunnerAgentSnapshot? = nil,
        enrollmentResult: Result<String, TestFailure> = .success("rhost_123"),
        snapshots: [RunnerAgentSnapshot] = [],
        streamCompletion: StreamCompletion = .finish,
        baselineGate: AsyncGate? = nil,
        enrollOperation: (@MainActor () async throws -> Void)? = nil
    ) {
        self.calls = calls
        self.baseline =
            baseline
            ?? RunnerAgentSnapshot(
                enrollment: .unenrolled,
                hostID: nil,
                isDraining: false,
                capabilities: [],
                inFlightJobs: [],
                recentVerdicts: [],
                telemetry: nil,
                settings: nil
            )
        self.enrollmentResult = enrollmentResult
        self.snapshots = snapshots
        self.streamCompletion = streamCompletion
        self.baselineGate = baselineGate
        self.enrollOperation = enrollOperation
    }

    func enroll(token: String, controlPlane: String?) async throws -> String {
        calls.record("enroll")
        receivedTokens.append(token)
        try await enrollOperation?()
        return try enrollmentResult.get()
    }

    func watchSnapshots() -> AsyncThrowingStream<RunnerAgentSnapshot, Error> {
        calls.record("watch")
        let baseline = baseline
        let snapshots = snapshots
        let streamCompletion = streamCompletion
        let baselineGate = baselineGate

        return AsyncThrowingStream { continuation in
            let task = Task {
                if let baselineGate {
                    await baselineGate.wait()
                }
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                continuation.yield(baseline)
                for snapshot in snapshots {
                    continuation.yield(snapshot)
                }
                if case .finish = streamCompletion {
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private enum TestFailure: Error, Sendable {
    case expected
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

extension TestFailure: LocalizedError {
    var errorDescription: String? {
        "Expected test failure."
    }
}

private func waitForCancellation(_: Duration) async throws {
    while !Task.isCancelled {
        await Task.yield()
    }
    throw CancellationError()
}
