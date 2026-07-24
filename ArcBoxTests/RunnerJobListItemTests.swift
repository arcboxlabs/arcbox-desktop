import FleetControlClient
import FleetPlatformClient
import XCTest

@testable import ArcBox

final class RunnerJobListItemTests: XCTestCase {
    func testMergeKeepsLiveOnlyJobsAheadOfPlatformHistory() {
        let platformJob = job(id: "job_finished", status: .completed)
        let liveJob = FleetInFlightJob(jobID: "job_live", os: "darwin", arch: "arm64")

        let items = RunnerJobListItem.merge(
            platformJobs: [platformJob],
            liveJobs: [liveJob]
        )

        XCTAssertEqual(items.map(\.id), ["job_live", "job_finished"])
        XCTAssertEqual(items.first?.status, .running)
        XCTAssertNil(items.first?.repository)
        XCTAssertEqual(items.last?.repository, "arcboxlabs/arcbox")
    }

    func testMergeDoesNotDuplicatePlatformJobReportedLiveByAgent() {
        let platformJob = job(id: "job_current", status: .provisioning)
        let liveJob = FleetInFlightJob(jobID: "job_current", os: "darwin", arch: "arm64")

        let items = RunnerJobListItem.merge(
            platformJobs: [platformJob],
            liveJobs: [liveJob]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "job_current")
        XCTAssertEqual(items.first?.status, .running)
        XCTAssertEqual(items.first?.repository, "arcboxlabs/arcbox")
    }

    private func job(id: String, status: FleetRunnerJobStatus) -> FleetRunnerJob {
        FleetRunnerJob(
            id: id,
            repo: "arcboxlabs/arcbox",
            status: status,
            os: .darwin,
            arch: .arm64,
            githubRunID: 123,
            githubJobID: 456,
            labels: [],
            machineID: "fltm_local",
            jitRunnerName: nil,
            createdAt: .distantPast,
            startedAt: nil,
            finishedAt: nil
        )
    }
}
