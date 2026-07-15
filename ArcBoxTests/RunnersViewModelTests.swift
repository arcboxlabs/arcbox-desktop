import FleetControlClient
import XCTest

@testable import ArcBox

@MainActor
final class RunnersViewModelTests: XCTestCase {
    func testInitialStateConnectsWithoutShowingEmptyState() {
        let vm = RunnersViewModel()

        XCTAssertEqual(vm.viewState, .connecting)
    }

    func testMissingControlClientShowsUnavailableState() {
        let vm = RunnersViewModel()

        vm.start(controlClient: nil, platformClient: nil)

        XCTAssertEqual(vm.viewState, .unavailable("Fleet control client is unavailable."))
    }

    func testValidUnenrolledSnapshotReflectsCurrentAuthentication() {
        let snapshot = makeSnapshot(enrollment: .unenrolled, machineID: nil)

        XCTAssertEqual(
            resolve(snapshot: snapshot, enrollmentState: .idle, isSignedIn: false),
            .signedOut
        )
        XCTAssertEqual(
            resolve(snapshot: snapshot, enrollmentState: .idle, isSignedIn: true),
            .unenrolled
        )
    }

    func testAttachedSnapshotMapsLiveJobsAndCapabilities() throws {
        let fleet = FleetViewModel()
        let job = FleetInFlightJob(jobID: "rjob_123", os: "darwin", arch: "arm64")
        let capability = FleetCapability(os: "darwin", arch: "arm64", backend: .vm)
        let snapshot = makeSnapshot(
            enrollment: .attached,
            capabilities: [capability],
            jobs: [job]
        )
        fleet.agentInfo = FleetAgentInfo(agentVersion: "0.5.0", apiVersion: 1, features: [])
        fleet.snapshot = snapshot
        fleet.loadState = .ready

        let vm = RunnersViewModel(fleet: fleet)
        let host = try XCTUnwrap(enrolledHost(from: vm.viewState))

        XCTAssertEqual(host.machineID, "fltm_test")
        XCTAssertEqual(host.status, .online)
        XCTAssertEqual(host.capabilities, [capability])
        XCTAssertEqual(host.inFlightJobs, [job])
        XCTAssertEqual(host.agentVersion, "0.5.0")
        XCTAssertEqual(vm.activeJobCount, 1)
    }

    func testDrainingSnapshotOverridesAttachedStatus() throws {
        let fleet = FleetViewModel()
        let snapshot = makeSnapshot(enrollment: .attached, isDraining: true)
        fleet.snapshot = snapshot
        fleet.loadState = .ready

        let vm = RunnersViewModel(fleet: fleet)
        let host = try XCTUnwrap(enrolledHost(from: vm.viewState))

        XCTAssertEqual(host.status, .draining)
        XCTAssertTrue(host.isDraining)
    }

    func testUpdatingSnapshotRemainsEnrolledAndDisablesDrainControl() throws {
        let state = resolve(
            snapshot: makeSnapshot(enrollment: .updating),
            enrollmentState: .ready(machineID: "fltm_test"),
            isSignedIn: true
        )
        let host = try XCTUnwrap(enrolledHost(from: state))

        XCTAssertEqual(host.status, .updating)
        XCTAssertFalse(host.status.canChangeDrainState)
    }

    func testEnrollmentCoordinatorPhasesMapToVisibleProgress() {
        let snapshot = makeSnapshot(enrollment: .unenrolled, machineID: nil)
        let cases: [(FleetEnrollmentCoordinator.State, RunnerEnrollmentProgress)] = [
            (.preparingAgent, .checkingAgent),
            (.requestingEnrollmentToken, .requestingToken),
            (.enrolling, .enrollingAgent),
            (.reconcilingEnrollment, .reconciling),
            (.attaching(machineID: "fltm_test"), .attaching),
            (.ready(machineID: "fltm_test"), .synchronizing),
        ]

        for (coordinatorState, progress) in cases {
            XCTAssertEqual(
                resolve(
                    snapshot: snapshot,
                    enrollmentState: coordinatorState,
                    isSignedIn: true
                ),
                .enrolling(progress)
            )
        }
    }

    func testCoordinatorFailureIsVisibleInsteadOfLeavingDisabledOnboarding() {
        let state = resolve(
            snapshot: makeSnapshot(enrollment: .unenrolled, machineID: nil),
            enrollmentState: .failed(.workspaceRequired),
            isSignedIn: true
        )

        XCTAssertEqual(
            state,
            .enrollmentFailed(
                "An ArcBox workspace is required for enrollment.",
                recovery: .retry
            )
        )
    }

    func testUnknownEnrollmentOutcomeDoesNotOfferUnsafeRetry() {
        let state = resolve(
            snapshot: makeSnapshot(enrollment: .unenrolled, machineID: nil),
            enrollmentState: .failed(.enrollmentOutcomeUnknown),
            isSignedIn: true,
            canBeginEnrollment: false
        )

        XCTAssertEqual(
            state,
            .enrollmentFailed(
                "The enrollment result is unknown. ArcBox will keep reconciling the Fleet Agent state.",
                recovery: .waitForAgent
            )
        )
    }

    func testKnownPostHandoffFailureOffersUnenrollRecovery() {
        let state = resolve(
            snapshot: makeSnapshot(enrollment: .unenrolled, machineID: nil),
            enrollmentState: .failed(.attachmentTimedOut(machineID: "fltm_test")),
            isSignedIn: true,
            canBeginEnrollment: false
        )

        XCTAssertEqual(
            state,
            .enrollmentFailed(
                "This Mac enrolled, but did not attach to the Fleet gateway in time.",
                recovery: .unenroll
            )
        )
    }

    func testEnrolledSnapshotWinsOverAuthenticationAndCoordinatorState() throws {
        let state = resolve(
            snapshot: makeSnapshot(enrollment: .credentialRejected),
            enrollmentState: .failed(.workspaceRequired),
            isSignedIn: false
        )
        let host = try XCTUnwrap(enrolledHost(from: state))

        XCTAssertEqual(host.status, .credentialRejected)
    }

    func testInvalidAndUnknownSnapshotsNeverShowOnboarding() {
        let invalidSnapshots = [
            makeSnapshot(enrollment: .unenrolled, machineID: "fltm_invalid"),
            makeSnapshot(enrollment: .attached, machineID: nil),
            makeSnapshot(enrollment: .updating, machineID: nil),
            makeSnapshot(enrollment: .unspecified, machineID: nil),
            makeSnapshot(enrollment: .unrecognized(42), machineID: nil),
        ]

        for snapshot in invalidSnapshots {
            let state = resolve(
                snapshot: snapshot,
                enrollmentState: .idle,
                isSignedIn: true
            )

            guard case .failed = state else {
                XCTFail("Invalid snapshot must fail closed, got \(state)")
                continue
            }
        }
    }

    func testRetainedHostIsMarkedReconnectingWhenWatchFails() {
        let state = resolve(
            snapshot: makeSnapshot(enrollment: .attached),
            loadState: .failed("State stream ended."),
            enrollmentState: .ready(machineID: "fltm_test"),
            isSignedIn: true
        )

        guard case .enrolled(_, freshness: .reconnecting(let message)) = state else {
            XCTFail("Expected a retained host marked as reconnecting, got \(state)")
            return
        }
        XCTAssertEqual(message, "State stream ended.")
    }

    func testRetainedUnenrolledSnapshotCannotStartEnrollmentWhileWatchReconnects() {
        let state = resolve(
            snapshot: makeSnapshot(enrollment: .unenrolled, machineID: nil),
            loadState: .failed("State stream ended."),
            enrollmentState: .idle,
            isSignedIn: true
        )

        XCTAssertEqual(state, .unavailable("State stream ended."))
    }

    func testCoordinatorReadyWithoutSnapshotDoesNotSynthesizeHost() {
        XCTAssertEqual(
            resolve(
                snapshot: nil,
                loadState: .ready,
                enrollmentState: .ready(machineID: "fltm_test"),
                isSignedIn: true
            ),
            .connecting
        )
    }

    private func makeSnapshot(
        enrollment: FleetEnrollmentState,
        machineID: String? = "fltm_test",
        isDraining: Bool = false,
        capabilities: [FleetCapability] = [],
        jobs: [FleetInFlightJob] = []
    ) -> FleetAgentSnapshot {
        FleetAgentSnapshot(
            enrollment: enrollment,
            machineID: machineID,
            isDraining: isDraining,
            capabilities: capabilities,
            inFlightJobs: jobs,
            recentVerdicts: [],
            telemetry: nil,
            settings: nil
        )
    }

    private func resolve(
        snapshot: FleetAgentSnapshot?,
        loadState: FleetLoadState = .ready,
        enrollmentState: FleetEnrollmentCoordinator.State?,
        isSignedIn: Bool?,
        canBeginEnrollment: Bool? = true
    ) -> RunnersViewState {
        RunnersViewModel.resolveViewState(
            snapshot: snapshot,
            agentInfo: nil,
            loadState: loadState,
            enrollmentContext: enrollmentState.map {
                RunnersViewModel.EnrollmentContext(
                    state: $0,
                    isSignedIn: isSignedIn ?? false,
                    canBeginEnrollment: canBeginEnrollment ?? false
                )
            }
        )
    }

    private func enrolledHost(from state: RunnersViewState) -> RunnerHostViewModel? {
        guard case .enrolled(let host, freshness: _) = state else { return nil }
        return host
    }
}
