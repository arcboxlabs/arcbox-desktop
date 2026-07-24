import FleetPlatformClient
import XCTest

@testable import ArcBox

final class RunnerHostJobSummaryTests: XCTestCase {
    func testSummaryCountsTodayAndUsesOnlyFinishedJobsForSuccessRate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 12))
        )
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let jobs = [
            job(id: "completed", status: .completed, createdAt: now),
            job(id: "failed", status: .failed, createdAt: now),
            job(id: "running", status: .running, createdAt: now),
            job(id: "old", status: .completed, createdAt: yesterday),
        ]

        let summary = RunnerHostJobSummary(
            jobs: jobs,
            hasMoreHistory: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.recordedCount, 4)
        XCTAssertEqual(summary.todayCount, 3)
        XCTAssertEqual(summary.completedCount, 2)
        XCTAssertEqual(summary.unsuccessfulCount, 1)
        XCTAssertEqual(summary.successRate, 2.0 / 3.0)
        XCTAssertEqual(summary.recordedCountDescription, "4")
    }

    func testSummaryMarksTruncatedHistoryAndOmitsRateWithoutFinishedJobs() {
        let summary = RunnerHostJobSummary(
            jobs: [job(id: "queued", status: .queued, createdAt: .now)],
            hasMoreHistory: true
        )

        XCTAssertEqual(summary.recordedCountDescription, "1+")
        XCTAssertNil(summary.successRate)
    }

    private func job(
        id: String,
        status: FleetRunnerJobStatus,
        createdAt: Date
    ) -> FleetRunnerJob {
        FleetRunnerJob(
            id: id,
            repo: "arcboxlabs/arcbox",
            status: status,
            os: .darwin,
            arch: .arm64,
            githubRunID: 1,
            githubJobID: 2,
            labels: [],
            machineID: "fltm_local",
            jitRunnerName: nil,
            createdAt: createdAt,
            startedAt: nil,
            finishedAt: nil
        )
    }
}
