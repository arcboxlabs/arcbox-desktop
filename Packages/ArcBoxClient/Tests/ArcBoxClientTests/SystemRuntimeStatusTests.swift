import XCTest

@testable import ArcBoxClient

@MainActor
final class SystemRuntimeStatusTests: XCTestCase {
    /// A daemon now reaches host READY before it boots the System VM, so Docker waits for
    /// the System runtime. A daemon that predates `system_runtime` only reached READY with
    /// Docker up, and its phase still decides.
    func testDockerReadinessFollowsTheSystemRuntimeOnceTheDaemonReportsIt() {
        let daemon = DaemonManager()
        var status = Arcbox_V1_SetupStatus()
        status.phase = .ready
        daemon.applySetupStatusSync(status)
        XCTAssertTrue(daemon.isDockerReady, "a daemon without system_runtime lost Docker readiness")

        status.systemRuntime = .with {
            $0.state = .vmReady
            $0.reason = "System VM ready; waiting for Docker"
        }
        daemon.applySetupStatusSync(status)
        XCTAssertFalse(daemon.isDockerReady, "host READY was taken for Docker readiness")
        XCTAssertNil(daemon.systemRuntimeIssue)
        XCTAssertEqual(daemon.runtimeProgressMessage, "System VM ready; waiting for Docker")

        status.systemRuntime.state = .ready
        daemon.applySetupStatusSync(status)
        XCTAssertTrue(daemon.isDockerReady)

        status.phase = .networkReady
        daemon.applySetupStatusSync(status)
        XCTAssertFalse(daemon.isDockerReady, "System READY without host READY")
    }

    /// Download progress lives exactly as long as DOWNLOADING. A size the server has not
    /// reported arrives as 0, and STARTING after the install carries no download.
    func testDownloadProgressLastsAsLongAsTheDownload() {
        let daemon = DaemonManager()
        var status = Arcbox_V1_SetupStatus()
        status.phase = .ready
        status.systemRuntime = .with {
            $0.state = .downloading
            $0.reason = "Downloading QEMU 0.1.0"
            $0.download = .with {
                $0.component = .qemu
                $0.stage = .transferring
                $0.downloadedBytes = 8_056
                $0.totalBytes = 5_930_315
            }
        }
        daemon.applySetupStatusSync(status)
        XCTAssertEqual(
            daemon.runtimeDownload,
            RuntimeDownloadProgress(stage: .transferring, downloadedBytes: 8_056, totalBytes: 5_930_315))
        XCTAssertFalse(daemon.isDockerReady)
        XCTAssertNil(daemon.systemRuntimeIssue, "a download is progress, not an issue")
        XCTAssertEqual(daemon.runtimeProgressMessage, "Downloading QEMU 0.1.0")

        // Bytes kept from an interrupted attempt, before the server reported the size.
        status.systemRuntime.download.stage = .waitingToRetry
        status.systemRuntime.download.downloadedBytes = 1_048_576
        status.systemRuntime.download.totalBytes = 0
        daemon.applySetupStatusSync(status)
        XCTAssertEqual(
            daemon.runtimeDownload,
            RuntimeDownloadProgress(stage: .waitingToRetry, downloadedBytes: 1_048_576, totalBytes: nil))

        status.systemRuntime = .with {
            $0.state = .starting
            $0.reason = "Preparing the System VM"
        }
        daemon.applySetupStatusSync(status)
        XCTAssertNil(daemon.runtimeDownload, "the install finished, but its progress stayed")
    }

    /// Only a Mac that lacks hardware virtualization with no emulated backend is beyond a
    /// retry. A failure under emulation is the emulator's and can be retried, and a daemon
    /// that does not report the field never claims the Mac lacks virtualization.
    func testOnlyAFailureWithoutAnyBackendBlamesTheMac() {
        let reason = "System VM cannot start: this Mac does not provide hardware virtualization"
        func issue(hardwareVirtualization: Bool?, backend: Arcbox_V1_SystemVmBackend) -> SystemRuntimeIssue? {
            var status = Arcbox_V1_SetupStatus()
            status.phase = .ready
            status.systemRuntime = .with {
                $0.state = .failed
                $0.reason = reason
            }
            if let hardwareVirtualization {
                status.hardwareVirtualizationAvailable = hardwareVirtualization
            }
            status.effectiveBackend = backend
            let daemon = DaemonManager()
            daemon.applySetupStatusSync(status)
            return daemon.systemRuntimeIssue
        }

        XCTAssertEqual(issue(hardwareVirtualization: false, backend: .unspecified), .hardwareVirtualizationUnavailable)
        XCTAssertEqual(issue(hardwareVirtualization: false, backend: .qemu), .failed(reason: reason))
        XCTAssertEqual(issue(hardwareVirtualization: nil, backend: .unspecified), .failed(reason: reason))
        XCTAssertEqual(issue(hardwareVirtualization: true, backend: .vz), .failed(reason: reason))
    }

    /// The bundled daemon's version decides whether a Mac without hardware virtualization
    /// may start it, so the comparison has to be numeric and fail closed.
    func testSoftwareEmulationNeedsABundledDaemonAtOrAboveTheMinimum() throws {
        let minimum = try XCTUnwrap(EmbeddedRuntime.Version("v0.11.0"))
        func supports(_ bundled: String?) -> Bool {
            EmbeddedRuntime.supportsSoftwareEmulation(bundledVersion: bundled, minimum: minimum)
        }

        XCTAssertTrue(supports("v0.11.0"))
        XCTAssertTrue(supports("v0.12.3"))
        XCTAssertTrue(supports("v1.0.0"))
        XCTAssertFalse(supports("v0.10.12"))
        XCTAssertFalse(supports("v0.9.0"), "compared as strings")
        XCTAssertFalse(supports("v0.11"))
        XCTAssertFalse(supports("master"))
        XCTAssertFalse(supports(nil))
        XCTAssertFalse(
            EmbeddedRuntime.supportsSoftwareEmulation(bundledVersion: "v9.9.9", minimum: nil),
            "no release supports emulation until a minimum is set")
    }

    /// Retrying a failed System startup restarts the daemon, which stops every Machine and
    /// macOS guest it hosts, so that retry always asks first and names the Linux Machines
    /// it can list.
    func testARetryWarnsBeforeARestartStopsMachines() async {
        let daemon = DaemonManager()
        let orchestrator = StartupOrchestrator(
            daemonManager: daemon, onClientsNeeded: { throw CancellationError() })
        var status = Arcbox_V1_SetupStatus()
        status.phase = .ready
        status.systemRuntime.state = .vmStarting
        daemon.applySetupStatusSync(status)
        let whileStarting = await orchestrator.retryWarning()
        XCTAssertNil(whileStarting, "a retry that keeps the daemon warned")

        status.phase = .failed
        status.systemRuntime.state = .failed
        daemon.applySetupStatusSync(status)
        let whileExiting = await orchestrator.retryWarning()
        XCTAssertNil(whileExiting, "a daemon in FAILED exits on its own")

        status.phase = .ready
        daemon.applySetupStatusSync(status)
        let generic =
            "Retrying restarts the ArcBox daemon, which stops any running machines and macOS virtual machines."
        let unlisted = await orchestrator.retryWarning()
        XCTAssertEqual(unlisted, generic, "an unlisted daemon is not one without Machines")

        func machine(_ name: String, _ state: String) -> Arcbox_V1_MachineSummary {
            .with {
                $0.id = name
                $0.name = name
                $0.state = state
            }
        }
        let systemVM = machine("default", "running")
        let stopped = machine("old", "stopped")
        XCTAssertEqual(
            StartupOrchestrator.restartWarning(listing: [systemVM, stopped]), generic,
            "no Linux Machine runs, but a macOS guest may")
        XCTAssertEqual(
            StartupOrchestrator.restartWarning(listing: [systemVM, machine("dev", "running"), stopped]),
            "Retrying restarts the ArcBox daemon, which stops the running machine dev, "
                + "as well as any running macOS virtual machines.")
        XCTAssertEqual(
            StartupOrchestrator.restartWarning(listing: [
                systemVM, machine("dev", "running"), machine("build", "starting"), stopped,
            ]),
            "Retrying restarts the ArcBox daemon, which stops the running machines dev and build, "
                + "as well as any running macOS virtual machines.")
    }
}
