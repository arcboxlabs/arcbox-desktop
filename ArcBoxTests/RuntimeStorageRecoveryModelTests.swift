import GRPCCore
import XCTest

@testable import ArcBox
@testable import ArcBoxClient

@MainActor
final class RuntimeStorageRecoveryModelTests: XCTestCase {
    func testCompleteIsTheOnlySuccessfulOutcome() async {
        let model = RuntimeStorageRecoveryModel { _, receive in
            receive(self.event(.verifying))
            receive(self.event(.complete))
        }
        model.start(.recover)
        await model.waitForCompletion()
        XCTAssertEqual(model.progress?.phase, .complete)
        XCTAssertEqual(model.progress?.statusLabel, "Read-write recovery completed")
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertNil(model.errorMessage)
    }

    func testStreamEndingDuringVerificationDoesNotClaimSuccess() async {
        let model = RuntimeStorageRecoveryModel { _, receive in receive(self.event(.verifying)) }
        model.start(.recover)
        await model.waitForCompletion()
        XCTAssertEqual(model.progress?.phase, .verifying)
        XCTAssertTrue(model.mayBeRunning)
        XCTAssertTrue(model.errorMessage?.contains("completion is unknown") == true)
    }

    func testStatusReplayResolvesInterruptedRecoveryAndRetainsDirectory() async {
        let model = RuntimeStorageRecoveryModel { _, receive in
            receive(self.event(.preserving, directory: "/tmp/preserved-pair"))
            throw RPCError(code: .unavailable, message: "stream disconnected")
        }
        model.start(.recover)
        await model.waitForCompletion()
        XCTAssertTrue(model.mayBeRunning)
        model.reconcile(event(.complete))
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertEqual(model.progress?.phase, .complete)
        XCTAssertEqual(model.progress?.recoveryDirectory, "/tmp/preserved-pair")
        XCTAssertNil(model.errorMessage)
        model.reconcile(event(.checking))
        XCTAssertEqual(model.progress?.phase, .complete)
    }

    func testUnknownPhaseAndDifferentOperationDoNotResolveActiveRecovery() async {
        var calls = 0
        let model = RuntimeStorageRecoveryModel { _, receive in
            calls += 1
            receive(self.event(.UNRECOGNIZED(99)))
        }
        model.start(.recover)
        await model.waitForCompletion()
        model.reconcile(event(.complete, id: "other"))
        model.start(.recover)
        XCTAssertTrue(model.mayBeRunning)
        XCTAssertEqual(model.progress?.phase, .UNRECOGNIZED(99))
        XCTAssertEqual(calls, 1)
    }

    func testReplayCannotBindRequestWhoseFirstStreamResponseWasLost() async {
        let model = RuntimeStorageRecoveryModel { _, _ in
            throw RPCError(code: .unavailable, message: "stream disconnected before the first response")
        }
        model.reconcile(event(.complete, id: "old"))
        model.start(.recover)
        model.reconcile(event(.complete, id: "old"))
        await model.waitForCompletion()
        XCTAssertTrue(model.mayBeRunning)
        XCTAssertNil(model.progress)
        model.reconcile(event(.failed, id: "new"))
        model.reconcile(event(.complete, id: "old"))
        XCTAssertTrue(model.mayBeRunning)
        XCTAssertNil(model.progress)
        XCTAssertTrue(model.errorMessage?.contains("completion is unknown") == true)
    }

    func testFirstTerminalReplayCannotCancelPendingRecoveryOrFinishTermination() async {
        for phase in [Arcbox_V1_StorageRecoveryProgress.Phase.complete, .failed] {
            let streamStarted = expectation(description: "Recovery stream started before the first replay")
            let directProgressReceived = expectation(description: "The direct stream still delivers progress")
            let waiterStarted = expectation(description: "Termination waiter started")
            let terminationFinished = expectation(description: "Termination waiter finished")
            let (events, continuation) = AsyncThrowingStream<Arcbox_V1_StorageRecoveryProgress, Error>.makeStream()
            var didFinishTermination = false
            let model = RuntimeStorageRecoveryModel { _, receive in
                streamStarted.fulfill()
                for try await progress in events {
                    receive(progress)
                    directProgressReceived.fulfill()
                }
            }
            model.start(.recover)
            await fulfillment(of: [streamStarted], timeout: 5)
            model.beginTermination()
            let termination = Task {
                waiterStarted.fulfill()
                await model.waitForCompletion()
                didFinishTermination = true
                terminationFinished.fulfill()
            }
            defer {
                continuation.finish()
                termination.cancel()
            }
            await fulfillment(of: [waiterStarted], timeout: 5)

            model.reconcile(event(phase, id: "old"))
            XCTAssertTrue(model.mayBeRunning)
            XCTAssertNil(model.progress)
            continuation.yield(event(.checking, id: "current"))
            await fulfillment(of: [directProgressReceived], timeout: 5)
            XCTAssertFalse(didFinishTermination)
            XCTAssertTrue(model.mayBeRunning)
            XCTAssertEqual(model.progress?.operationID, "current")

            model.reconcile(event(phase, id: "current"))
            await fulfillment(of: [terminationFinished], timeout: 5)
            continuation.finish()
            await termination.value
            XCTAssertFalse(model.mayBeRunning)
            XCTAssertEqual(model.progress?.operationID, "current")
            XCTAssertEqual(model.progress?.phase, phase)
            XCTAssertNil(model.errorMessage)
        }
    }

    func testEarlyTerminalReplayResolvesRecoveryOnlyAfterTheDirectStreamConfirmsItsID() async {
        for phase in [Arcbox_V1_StorageRecoveryProgress.Phase.complete, .failed] {
            let streamStarted = expectation(description: "Recovery stream started")
            let streamCancelled = expectation(description: "The matching terminal replay cancelled the stream")
            let (events, continuation) = AsyncThrowingStream<Arcbox_V1_StorageRecoveryProgress, Error>.makeStream()
            continuation.onTermination = { reason in
                if case .cancelled = reason { streamCancelled.fulfill() }
            }
            let model = RuntimeStorageRecoveryModel { _, receive in
                streamStarted.fulfill()
                for try await progress in events { receive(progress) }
            }
            model.start(.recover)
            await fulfillment(of: [streamStarted], timeout: 5)
            model.reconcile(event(phase, id: "current"))
            XCTAssertTrue(model.mayBeRunning)
            XCTAssertNil(model.progress)

            continuation.yield(event(.checking, id: "current", directory: "/tmp/preserved-pair"))
            await fulfillment(of: [streamCancelled], timeout: 5)
            continuation.finish()
            await model.waitForCompletion()
            XCTAssertFalse(model.mayBeRunning)
            XCTAssertEqual(model.progress?.operationID, "current")
            XCTAssertEqual(model.progress?.phase, phase)
            XCTAssertEqual(model.progress?.recoveryDirectory, "/tmp/preserved-pair")
            XCTAssertNil(model.errorMessage)
        }
    }

    func testEarlyNonterminalReplayDoesNotRegressDirectStreamProgress() async {
        let model = RuntimeStorageRecoveryModel { _, receive in
            receive(self.event(.verifying))
        }
        model.start(.recover)
        model.reconcile(event(.checking))
        await model.waitForCompletion()
        XCTAssertEqual(model.progress?.phase, .verifying)
        XCTAssertTrue(model.mayBeRunning)
    }

    func testDockerDataResetBlocksRecoveryAndDuplicateResetUntilItFinishes() async {
        let resetStarted = expectation(description: "Docker data reset started")
        let (events, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        var recoveryCalls = 0
        let model = RuntimeStorageRecoveryModel { _, receive in
            recoveryCalls += 1
            receive(self.event(.complete))
        }
        model.startDockerDataReset {
            resetStarted.fulfill()
            for await _ in events {}
        }
        XCTAssertTrue(model.isResettingDockerData)
        for action in [Arcbox_V1_RecoverStorageRequest.Action.checkOnly, .recover] {
            model.start(action)
        }
        model.startDockerDataReset { XCTFail("A reset must reject a duplicate reset") }
        await fulfillment(of: [resetStarted], timeout: 5)
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertNil(model.progress)
        XCTAssertEqual(recoveryCalls, 0)

        continuation.finish()
        await model.waitForCompletion()
        XCTAssertFalse(model.isResettingDockerData)
        model.start(.recover)
        await model.waitForCompletion()
        XCTAssertEqual(recoveryCalls, 1)
        XCTAssertEqual(model.progress?.phase, .complete)
    }

    func testRecoveryBlocksDockerDataResetUntilCompletionIsKnown() async {
        let model = RuntimeStorageRecoveryModel { _, receive in
            receive(self.event(.checking))
        }
        model.start(.recover)
        model.startDockerDataReset { XCTFail("A pending recovery must reject reset") }
        await model.waitForCompletion()
        model.startDockerDataReset { XCTFail("An interrupted recovery must reject reset") }
        await model.waitForCompletion()
        XCTAssertFalse(model.isResettingDockerData)
        XCTAssertTrue(model.mayBeRunning)

        model.reconcile(event(.complete))
        var resetCalls = 0
        model.startDockerDataReset { resetCalls += 1 }
        await model.waitForCompletion()
        XCTAssertEqual(resetCalls, 1)
        XCTAssertFalse(model.isResettingDockerData)
    }

    func testTerminationWaitsForDockerDataResetAndPreventsAnotherReset() async {
        let resetStarted = expectation(description: "Docker data reset started")
        let waiterStarted = expectation(description: "Termination waiter started")
        let terminationFinished = expectation(description: "Termination waiter finished")
        let (events, continuation) = AsyncStream<Void>.makeStream()
        var didFinishTermination = false
        let model = RuntimeStorageRecoveryModel { _, _ in XCTFail("Termination must prevent recovery") }
        model.startDockerDataReset {
            resetStarted.fulfill()
            for await _ in events {}
        }
        await fulfillment(of: [resetStarted], timeout: 5)
        model.beginTermination()
        let termination = Task {
            waiterStarted.fulfill()
            await model.waitForCompletion()
            didFinishTermination = true
            terminationFinished.fulfill()
        }
        defer {
            continuation.finish()
            termination.cancel()
        }
        await fulfillment(of: [waiterStarted], timeout: 5)
        XCTAssertTrue(model.isResettingDockerData)
        XCTAssertFalse(didFinishTermination)

        continuation.finish()
        await fulfillment(of: [terminationFinished], timeout: 5)
        await termination.value
        XCTAssertFalse(model.isResettingDockerData)
        model.startDockerDataReset { XCTFail("Termination must prevent reset") }
        model.start(.recover)
        await model.waitForCompletion()
        XCTAssertFalse(model.isResettingDockerData)
        XCTAssertFalse(model.mayBeRunning)
    }

    func testRestartFailureAndCheckOnlyCompletionAreReplayed() {
        let model = RuntimeStorageRecoveryModel { _, _ in XCTFail("Replay must not start recovery") }
        model.reconcile(event(.failed, directory: "/tmp/preserved-pair", storageProtected: true))
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertEqual(model.progress?.phase, .failed)
        XCTAssertEqual(model.progress?.storageProtected, true)
        model.reconcile(event(.complete, id: "check-only", storageProtected: true))
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertEqual(model.progress?.phase, .complete)
        XCTAssertEqual(model.progress?.storageProtected, true)
        XCTAssertEqual(model.progress?.statusLabel, "Storage checked; runtime remains stopped")
    }

    func testUnsupportedRuntimeRejectsRequestWithoutLeavingAnUnknownOperation() async {
        let model = RuntimeStorageRecoveryModel { _, _ in
            throw RPCError(code: .unimplemented, message: "Recovery is unavailable")
        }
        model.start(.checkOnly)
        await model.waitForCompletion()
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertNotNil(model.errorMessage)
    }

    func testTerminationPreventsNewRecovery() async {
        let model = RuntimeStorageRecoveryModel { _, _ in XCTFail("Termination must prevent recovery") }
        model.beginTermination()
        model.start(.recover)
        await model.waitForCompletion()
        XCTAssertFalse(model.mayBeRunning)
    }

    func testTerminationKeepsObservingStatusUntilPendingRecoveryCompletes() async {
        for phase in [Arcbox_V1_StorageRecoveryProgress.Phase.complete, .failed] {
            let daemon = DaemonManager()
            let streamStarted = expectation(description: "Recovery stream started")
            let streamCancelled = expectation(description: "Terminal status cancelled the pending stream")
            let waiterStarted = expectation(description: "Termination waiter started")
            let terminationFinished = expectation(description: "Termination waiter finished")
            let (events, continuation) = AsyncThrowingStream<Arcbox_V1_StorageRecoveryProgress, Error>.makeStream()
            continuation.onTermination = { reason in
                if case .cancelled = reason { streamCancelled.fulfill() }
            }
            var didFinishTermination = false
            let model = RuntimeStorageRecoveryModel { _, receive in
                receive(self.event(.checking, directory: "/tmp/preserved-pair"))
                streamStarted.fulfill()
                for try await progress in events {
                    receive(progress)
                }
            }
            model.observe(daemon)
            model.start(.recover)
            await fulfillment(of: [streamStarted], timeout: 5)

            model.beginTermination()
            let termination = Task {
                waiterStarted.fulfill()
                await model.waitForCompletion()
                didFinishTermination = true
                terminationFinished.fulfill()
            }
            defer {
                continuation.finish()
                termination.cancel()
            }
            await fulfillment(of: [waiterStarted], timeout: 5)
            XCTAssertFalse(didFinishTermination)
            XCTAssertTrue(model.mayBeRunning)

            var status = Arcbox_V1_SetupStatus()
            status.storageRecovery = event(phase, storageProtected: phase == .failed)
            daemon.applySetupStatusSync(status)
            await fulfillment(of: [streamCancelled, terminationFinished], timeout: 5)
            continuation.finish()
            await termination.value

            XCTAssertFalse(model.mayBeRunning)
            XCTAssertEqual(model.progress?.phase, phase)
            XCTAssertEqual(model.progress?.storageProtected, phase == .failed)
            XCTAssertEqual(model.progress?.recoveryDirectory, "/tmp/preserved-pair")
            XCTAssertNil(model.errorMessage)
        }
    }

    private func event(
        _ phase: Arcbox_V1_StorageRecoveryProgress.Phase,
        id: String = "operation",
        directory: String = "",
        storageProtected: Bool = false
    ) -> Arcbox_V1_StorageRecoveryProgress {
        .with {
            $0.phase = phase
            $0.operationID = id
            $0.recoveryDirectory = directory
            $0.storageProtected = storageProtected
        }
    }
}
