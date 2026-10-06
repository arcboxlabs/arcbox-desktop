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

    func testOldTerminalReplayCannotCompleteANewRequest() async {
        let model = RuntimeStorageRecoveryModel { _, _ in }
        model.reconcile(event(.complete, id: "old"))
        model.start(.recover)
        model.reconcile(event(.complete, id: "old"))
        await model.waitForCompletion()
        XCTAssertTrue(model.mayBeRunning)
        XCTAssertNil(model.progress)
        model.reconcile(event(.failed, id: "new"))
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertEqual(model.progress?.phase, .failed)
        model.reconcile(event(.complete, id: "old"))
        XCTAssertEqual(model.progress?.operationID, "new")
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
