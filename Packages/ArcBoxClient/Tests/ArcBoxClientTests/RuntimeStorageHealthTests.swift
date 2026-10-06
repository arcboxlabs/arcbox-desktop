import XCTest

@testable import ArcBoxClient

@MainActor
final class RuntimeStorageHealthTests: XCTestCase {
    func testReadOnlyStorageKeepsDockerAPIReady() {
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(status(data: .readOnly))

        XCTAssertEqual(daemon.state, .running)
        XCTAssertTrue(daemon.setupPhase.isDockerReady)
        XCTAssertTrue(daemon.storageHealthIsCurrent)
        XCTAssertTrue(daemon.storageWriteFailureMessage?.contains("Data: read-only") == true)
    }

    func testDisconnectRetainsObservationWithoutClaimingCurrentHealth() {
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(status(data: .readOnly))
        daemon.stopWatching()

        XCTAssertFalse(daemon.storageHealthIsCurrent)
        XCTAssertNil(daemon.storageWriteFailureMessage)
        XCTAssertEqual(daemon.storageHealth?.volumes.first?.state, .readOnly)
    }

    func testOlderRuntimeAndStoppedVMDoNotInheritHealthyState() {
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(status(data: .mountedReadWrite))
        var stopped = status(data: .mountedReadWrite)
        stopped.vmRunning = false
        daemon.applySetupStatusSync(stopped)
        XCTAssertFalse(daemon.storageHealthIsCurrent)

        var older = Arcbox_V1_SetupStatus()
        older.phase = .ready
        older.vmRunning = true
        daemon.applySetupStatusSync(older)
        XCTAssertFalse(daemon.storageHealthIsCurrent)
        XCTAssertNil(daemon.storageWriteFailureMessage)

        let freshDaemon = DaemonManager()
        freshDaemon.applySetupStatusSync(older)
        XCTAssertNil(freshDaemon.storageHealth)
    }

    func testUnknownWireValuesAreRetainedWithoutClaimingWritableStorage() {
        var proto = Arcbox_V1_StorageHealth()
        var volume = Arcbox_V1_StorageVolumeHealth()
        volume.role = .UNRECOGNIZED(12)
        volume.state = .UNRECOGNIZED(23)
        proto.volumes = [volume]
        let health = RuntimeStorageHealth(proto)

        XCTAssertEqual(health.volumes.first?.role, .unknown(12))
        XCTAssertEqual(health.volumes.first?.state, .unknown(23))
        XCTAssertNil(health.observedAt)
        XCTAssertNil(health.writeFailureMessage)
    }

    func testLegacyMetadataAbsenceAndMountingDoNotBlockWrites() {
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(status(data: .mountedReadWrite, metadata: .notConfigured))
        XCTAssertNil(daemon.storageWriteFailureMessage)

        var mounting = status(data: .unavailable)
        mounting.phase = .vmReady
        daemon.applySetupStatusSync(mounting)
        XCTAssertNil(daemon.storageWriteFailureMessage)
        mounting.phase = .ready
        daemon.applySetupStatusSync(mounting)
        XCTAssertNotNil(daemon.storageWriteFailureMessage)
    }

    func testMetadataFailureAndRecoveryUpdateTheWriteReason() {
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(status(data: .mountedReadWrite, metadata: .unavailable))
        XCTAssertTrue(daemon.storageWriteFailureMessage?.contains("Metadata: unavailable") == true)
        daemon.applySetupStatusSync(status(data: .mountedReadWrite))
        XCTAssertNil(daemon.storageWriteFailureMessage)
    }

    func testRecoveryBlocksWritesWhileMountObservationsAreUnavailable() {
        let daemon = DaemonManager()
        var recovering = Arcbox_V1_SetupStatus()
        recovering.phase = .ready
        recovering.storageRecovery.operationID = "operation"
        recovering.storageRecovery.phase = .checking
        daemon.applySetupStatusSync(recovering)
        XCTAssertTrue(daemon.storageWriteFailureMessage?.contains("recovery is in progress") == true)
        XCTAssertEqual(daemon.storageRecovery?.operationID, "operation")
        daemon.applySetupStatusSync(.init())
        XCTAssertNotNil(daemon.storageWriteFailureMessage)
        recovering.storageRecovery.phase = .complete
        daemon.applySetupStatusSync(recovering)
        XCTAssertNil(daemon.storageWriteFailureMessage)
    }

    func testCheckOnlyCompletionKeepsProtectionAcrossDisconnectAndReplay() {
        var checked = status(data: .mountedReadWrite)
        checked.vmRunning = false
        checked.storageRecovery.operationID = "check-only"
        checked.storageRecovery.phase = .complete
        checked.storageRecovery.storageProtected = true
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(checked)
        XCTAssertTrue(daemon.setupPhase.isDockerReady)
        XCTAssertFalse(daemon.storageHealthIsCurrent)
        XCTAssertTrue(daemon.storageWriteFailureMessage?.contains("remains protected") == true)

        daemon.stopWatching()
        daemon.applySetupStatusSync(.init())
        XCTAssertNotNil(daemon.storageWriteFailureMessage)
        let reconnected = DaemonManager()
        reconnected.applySetupStatusSync(checked)
        XCTAssertNotNil(reconnected.storageWriteFailureMessage)
    }

    func testRecoveryFailureKeepsProtectionUntilVerifiedCompletion() {
        var observation = status(data: .mountedReadWrite)
        observation.storageRecovery.operationID = "failed-recovery"
        observation.storageRecovery.phase = .failed
        observation.storageRecovery.storageProtected = true
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(observation)
        XCTAssertNotNil(daemon.storageWriteFailureMessage)

        observation.storageRecovery.operationID = "successful-recovery"
        observation.storageRecovery.phase = .complete
        observation.storageRecovery.storageProtected = false
        daemon.applySetupStatusSync(observation)
        XCTAssertNil(daemon.storageWriteFailureMessage)
    }

    private func status(
        data: Arcbox_V1_StorageVolumeHealth.State,
        metadata: Arcbox_V1_StorageVolumeHealth.State = .mountedReadWrite
    ) -> Arcbox_V1_SetupStatus {
        var status = Arcbox_V1_SetupStatus()
        status.phase = .ready
        status.vmRunning = true
        status.storageHealth.observedAtUnixMs = 1_800_000_000_000
        status.storageHealth.volumes = [
            .with {
                $0.role = .data; $0.state = data
            },
            .with {
                $0.role = .metadata; $0.state = metadata
            },
        ]
        return status
    }
}
