import XCTest

@testable import ArcBox
@testable import ArcBoxClient

@MainActor
final class RuntimeStorageRecoveryIntegrationTests: XCTestCase {
    func testRecoveryAgainstIsolatedRuntime() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let socket = environment["ARCBOX_LIVE_RECOVERY_SOCKET"] else {
            throw XCTSkip("Set ARCBOX_LIVE_RECOVERY_SOCKET to a disposable runtime socket.")
        }
        let actionName = try XCTUnwrap(environment["ARCBOX_LIVE_RECOVERY_ACTION"])
        let action = try XCTUnwrap(
            ["check": Arcbox_V1_RecoverStorageRequest.Action.checkOnly, "recover": .recover][actionName])
        let expectedOperation = environment["ARCBOX_LIVE_RECOVERY_EXPECTED_OPERATION"]
        if action == .recover {
            XCTAssertFalse(try XCTUnwrap(expectedOperation).isEmpty)
        }

        let client = try ArcBoxClient(socketPath: socket)
        let connection = Task { try await client.runConnections() }
        let daemon = DaemonManager()
        defer {
            daemon.stopWatching()
            client.close()
            connection.cancel()
        }
        let model = RuntimeStorageRecoveryModel(clientProvider: { client })
        model.observe(daemon)
        daemon.connectAndWatch(client: client)

        if action == .recover {
            try await waitUntil("The restarted daemon must replay the protected check-only operation.") {
                model.progress?.operationID == expectedOperation && model.progress?.phase == .complete
                    && model.progress?.storageProtected == true && !daemon.vmRunning
            }
            XCTAssertNotNil(daemon.storageWriteFailureMessage)
        } else {
            try await waitUntil("The disposable runtime must be ready before check-only.") {
                daemon.setupPhase.isDockerReady && daemon.vmRunning
            }
        }

        model.start(action)
        try await waitUntil("Recovery must report a terminal result or an error.") {
            model.progress?.phase.isTerminal == true || model.errorMessage != nil
        }
        await model.waitForCompletion()
        XCTAssertNil(model.errorMessage)
        let progress = try XCTUnwrap(
            model.progress?.phase == .complete ? model.progress : nil,
            model.progress?.message ?? "No recovery result")
        XCTAssertFalse(model.mayBeRunning)
        XCTAssertFalse(progress.operationID.isEmpty)
        XCTAssertFalse(progress.recoveryDirectory.isEmpty)
        XCTAssertNotEqual(progress.operationID, expectedOperation)
        XCTAssertEqual(progress.storageProtected, action == .checkOnly)
        XCTAssertEqual(
            progress.statusLabel,
            action == .checkOnly ? "Storage checked; runtime remains stopped" : "Read-write recovery completed")

        try await waitUntil("WatchSetupStatus must agree with the recovery result and VM state.") {
            daemon.storageRecovery?.operationID == progress.operationID
                && daemon.storageRecovery?.phase == .complete
                && daemon.storageRecovery?.storageProtected == progress.storageProtected
                && daemon.vmRunning == (action == .recover)
        }
        if action == .checkOnly {
            XCTAssertNotNil(daemon.storageWriteFailureMessage)
        } else {
            XCTAssertNil(daemon.storageWriteFailureMessage)
        }
        daemon.stopWatching()
        client.close()
        connection.cancel()
        try await connection.value
    }

    private func waitUntil(_ message: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try XCTUnwrap(condition() ? true : nil, message)
    }
}
