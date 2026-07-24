import FleetControlClient
import FleetPlatformClient
import XCTest

@testable import ArcBox

final class RunnerJobDetailModelTests: XCTestCase {
    func testResolveUsesPlatformMetadataAndLiveRunningState() throws {
        let platformJob = job(id: "job_current", status: .provisioning)
        let liveJob = FleetInFlightJob(jobID: "job_current", os: "darwin", arch: "arm64")

        let detail = try XCTUnwrap(
            RunnerJobDetailModel.resolve(
                id: "job_current",
                platformJobs: [platformJob],
                liveJobs: [liveJob]
            )
        )

        XCTAssertEqual(detail.repository, "arcboxlabs/arcbox")
        XCTAssertEqual(detail.status, .running)
        XCTAssertEqual(detail.machineID, "fltm_local")
        XCTAssertEqual(
            detail.githubURL?.absoluteString,
            "https://github.com/arcboxlabs/arcbox/actions/runs/123/job/456"
        )
    }

    func testResolveSupportsLiveOnlyJobWithoutInventingPlatformMetadata() throws {
        let liveJob = FleetInFlightJob(jobID: "job_live", os: "linux", arch: "arm64")

        let detail = try XCTUnwrap(
            RunnerJobDetailModel.resolve(
                id: "job_live",
                platformJobs: [],
                liveJobs: [liveJob]
            )
        )

        XCTAssertEqual(detail.status, .running)
        XCTAssertEqual(detail.runtimeKind, "Docker container")
        XCTAssertNil(detail.repository)
        XCTAssertNil(detail.githubURL)
        XCTAssertNil(detail.machineID)
    }

    func testLiveMacOSJobUsesVirtualMachineRuntime() throws {
        let liveJob = FleetInFlightJob(jobID: "job_live", os: "macos", arch: "arm64")

        let detail = try XCTUnwrap(
            RunnerJobDetailModel.resolve(
                id: "job_live",
                platformJobs: [],
                liveJobs: [liveJob]
            )
        )

        XCTAssertEqual(detail.runtimeKind, "Virtual machine")
    }

    func testResolveReturnsNilForUnknownJob() {
        XCTAssertNil(
            RunnerJobDetailModel.resolve(
                id: "missing",
                platformJobs: [],
                liveJobs: []
            )
        )
    }

    func testGitHubURLRejectsMalformedRepository() throws {
        let detail = try XCTUnwrap(
            RunnerJobDetailModel.resolve(
                id: "job",
                platformJobs: [job(id: "job", status: .completed, repo: "not-a-repo")],
                liveJobs: []
            )
        )

        XCTAssertNil(detail.githubURL)
    }

    private func job(
        id: String,
        status: FleetRunnerJobStatus,
        repo: String = "arcboxlabs/arcbox"
    ) -> FleetRunnerJob {
        FleetRunnerJob(
            id: id,
            repo: repo,
            status: status,
            os: .darwin,
            arch: .arm64,
            githubRunID: 123,
            githubJobID: 456,
            labels: ["self-hosted", "macOS"],
            machineID: "fltm_local",
            jitRunnerName: "arcbox-jit-123",
            createdAt: .distantPast,
            startedAt: .distantPast,
            finishedAt: status == .completed ? .now : nil
        )
    }
}
