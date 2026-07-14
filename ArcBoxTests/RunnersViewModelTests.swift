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

    func testUnenrolledSnapshotShowsOnboarding() {
        let fleet = FleetViewModel()
        let snapshot = makeSnapshot(enrollment: .unenrolled)
        fleet.snapshot = snapshot
        fleet.loadState = .ready(snapshot)

        let vm = RunnersViewModel(fleet: fleet)

        XCTAssertEqual(vm.viewState, .unenrolled)
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
        fleet.loadState = .ready(snapshot)

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
        fleet.loadState = .ready(snapshot)

        let vm = RunnersViewModel(fleet: fleet)
        let host = try XCTUnwrap(enrolledHost(from: vm.viewState))

        XCTAssertEqual(host.status, .draining)
        XCTAssertTrue(host.isDraining)
    }

    private func makeSnapshot(
        enrollment: FleetEnrollmentState,
        isDraining: Bool = false,
        capabilities: [FleetCapability] = [],
        jobs: [FleetInFlightJob] = []
    ) -> FleetAgentSnapshot {
        FleetAgentSnapshot(
            enrollment: enrollment,
            machineID: enrollment == .unenrolled ? nil : "fltm_test",
            isDraining: isDraining,
            capabilities: capabilities,
            inFlightJobs: jobs,
            recentVerdicts: [],
            telemetry: nil,
            settings: nil
        )
    }

    private func enrolledHost(from state: RunnersViewState) -> RunnerHostViewModel? {
        guard case .enrolled(let host) = state else { return nil }
        return host
    }
}
