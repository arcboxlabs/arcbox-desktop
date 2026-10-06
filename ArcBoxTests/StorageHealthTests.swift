import SwiftTerm
import XCTest

@testable import ArcBox
@testable import ArcBoxClient

@MainActor
final class StorageHealthTests: XCTestCase {
    func testNotificationDeduplicatesAcrossObservationsAndReconnects() {
        var rules = StorageNotificationRules()
        let fault = health(data: .readOnly)
        XCTAssertNotNil(rules.notification(for: fault, isCurrent: true, isRuntimeReady: true))
        XCTAssertNil(rules.notification(for: fault, isCurrent: true, isRuntimeReady: true))
        XCTAssertNil(rules.notification(for: nil, isCurrent: false, isRuntimeReady: true))
        XCTAssertNil(rules.notification(for: fault, isCurrent: true, isRuntimeReady: true))
        XCTAssertNil(rules.notification(for: health(data: .unspecified), isCurrent: true, isRuntimeReady: true))
        XCTAssertNil(rules.notification(for: fault, isCurrent: true, isRuntimeReady: true))
    }

    func testHealthyObservationEndsIncidentAndOtherVolumeFailureNotifies() {
        var rules = StorageNotificationRules()
        let fault = health(data: .readOnly)
        let first = rules.notification(for: fault, isCurrent: true, isRuntimeReady: true)
        let second = rules.notification(
            for: health(data: .readOnly, metadata: .unavailable), isCurrent: true, isRuntimeReady: true)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.identifier, second?.identifier)
        XCTAssertNil(rules.notification(for: health(data: .mountedReadWrite), isCurrent: true, isRuntimeReady: true))
        XCTAssertNotNil(rules.notification(for: fault, isCurrent: true, isRuntimeReady: true))
    }

    func testInitialMountAndStaleFaultDoNotNotify() {
        var rules = StorageNotificationRules()
        let unavailable = health(data: .unavailable)
        XCTAssertNil(rules.notification(for: unavailable, isCurrent: true, isRuntimeReady: false))
        XCTAssertNil(rules.notification(for: unavailable, isCurrent: false, isRuntimeReady: true))
        XCTAssertNotNil(rules.notification(for: unavailable, isCurrent: true, isRuntimeReady: true))
    }

    func testDiagnosticsIncludeBothVolumesAndFreshness() {
        let daemon = DaemonManager()
        daemon.storageHealth = health(data: .readOnly, metadata: .unavailable)
        daemon.storageRecovery = .with {
            $0.operationID = "check-only"
            $0.phase = .complete
            $0.storageProtected = true
        }
        let report = DiagnosticBundleExporter.storageHealthSection(daemon)
        XCTAssertTrue(report.contains("Current observation: false"))
        XCTAssertTrue(report.contains("Storage writes protected: true"))
        XCTAssertTrue(report.contains("Data: Read-only"))
        XCTAssertTrue(report.contains("Metadata: Unavailable"))
        XCTAssertTrue(report.contains("mount: /mnt/data; filesystem: btrfs"))
        XCTAssertTrue(report.contains("Detail: write I/O failed"))
        XCTAssertTrue(report.contains("Read-write mounting does not prove durable writes succeed."))
    }

    func testKnownStorageFailureStopsExplicitWritesBeforeDockerCalls() async {
        let reason = "Runtime storage cannot accept writes."
        let containers = ContainersViewModel()
        containers.storageWriteFailure = { reason }
        let container = await containers.createContainer(
            options: ContainerCreateOptions(
                image: "postgres:18", name: "", platform: nil, command: "", entrypoint: "", workingDir: "",
                autoRemove: false, restartPolicy: "no", privileged: false, readOnlyRootfs: false, dockerInit: false),
            docker: nil)
        XCTAssertNil(container)
        XCTAssertEqual(containers.lastError, reason)

        let images = ImagesViewModel()
        images.storageWriteFailure = { reason }
        let pulled = await images.pullImage("postgres:18", platform: nil, docker: nil)
        XCTAssertFalse(pulled)
        XCTAssertEqual(images.lastError, reason)
        let imported = await images.importImage(tarURL: URL(fileURLWithPath: "/missing.tar"), docker: nil)
        XCTAssertFalse(imported)
        XCTAssertEqual(images.lastError, reason)

        let volumes = VolumesViewModel()
        volumes.storageWriteFailure = { reason }
        let created = await volumes.createVolume(name: "test", docker: nil)
        XCTAssertFalse(created)
        XCTAssertEqual(volumes.lastError, reason)
        let volumeImported = await volumes.importVolume(
            name: "test", tarURL: URL(fileURLWithPath: "/missing.tar"), docker: nil)
        XCTAssertFalse(volumeImported)
        XCTAssertEqual(volumes.lastError, reason)
    }

    func testReadOnlyStorageStopsTemporaryImageContainersBeforeLaunchingCLI() {
        let session = DockerTerminalSession()
        session.storageWriteFailure = { "Runtime storage is read-only." }
        session.runImage(imageName: "postgres:18", shell: "/bin/sh", terminalView: TerminalView())
        XCTAssertEqual(session.state, .error("Runtime storage is read-only."))
        XCTAssertNil(session.activeImageContainerName)
    }

    private func health(
        data: Arcbox_V1_StorageVolumeHealth.State,
        metadata: Arcbox_V1_StorageVolumeHealth.State = .mountedReadWrite
    ) -> RuntimeStorageHealth {
        RuntimeStorageHealth(
            .with {
                $0.observedAtUnixMs = 1_800_000_000_000
                $0.volumes = [
                    .with {
                        $0.role = .data
                        $0.state = data
                        $0.device = "/dev/vdb"
                        $0.mountPoint = "/mnt/data"
                        $0.filesystem = "btrfs"
                        $0.detail = "write I/O failed"
                    },
                    .with {
                        $0.role = .metadata; $0.state = metadata
                    },
                ]
            })
    }
}
