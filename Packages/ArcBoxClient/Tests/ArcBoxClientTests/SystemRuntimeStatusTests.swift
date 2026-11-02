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

    /// Only a Mac that lacks hardware virtualization is beyond a retry, and a daemon that
    /// does not report the field never claims the Mac lacks virtualization.
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
        XCTAssertEqual(issue(hardwareVirtualization: nil, backend: .unspecified), .failed(reason: reason))
        XCTAssertEqual(issue(hardwareVirtualization: true, backend: .vz), .failed(reason: reason))
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
