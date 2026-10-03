import ProcessSupportTesting
import XCTest

@testable import ArcBox

final class TimeMachineExclusionTests: XCTestCase {
    private var root: URL!
    private var dataPath: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("time-machine-\(UUID().uuidString)")
        dataPath = root.appendingPathComponent("data").path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testExcludingCreatesTheDirectoryAndAddsTheExclusion() async throws {
        let tmutil = try await FakeExecutable.recordingArguments()
        defer { tmutil.remove() }

        try await TimeMachineExclusion(tmutilPath: tmutil.path).update(dataPath, includeInBackups: false)

        XCTAssertEqual(try tmutil.recordedArguments(), ["addexclusion", dataPath])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataPath), "tmutil refuses a path that does not exist")
    }

    func testIncludingRemovesTheExclusion() async throws {
        let tmutil = try await FakeExecutable.recordingArguments()
        defer { tmutil.remove() }

        try await TimeMachineExclusion(tmutilPath: tmutil.path).update(dataPath, includeInBackups: true)

        XCTAssertEqual(try tmutil.recordedArguments(), ["removeexclusion", dataPath])
    }

    func testFailureReportsTmutilsStderr() async throws {
        let tmutil = try await FakeExecutable.recordingArguments(
            exitingWith: 1, standardError: "tmutil: addexclusion requires Full Disk Access privileges.\n")
        defer { tmutil.remove() }

        do {
            try await TimeMachineExclusion(tmutilPath: tmutil.path).update(dataPath, includeInBackups: false)
            XCTFail("a failing tmutil must throw")
        } catch TimeMachineExclusionError.commandFailed(let detail) {
            XCTAssertEqual(detail, "tmutil: addexclusion requires Full Disk Access privileges.")
        }
    }

    func testASilentFailureReportsTheExitStatus() async throws {
        let tmutil = try await FakeExecutable.recordingArguments(exitingWith: 3)
        defer { tmutil.remove() }

        do {
            try await TimeMachineExclusion(tmutilPath: tmutil.path).update(dataPath, includeInBackups: false)
            XCTFail("a failing tmutil must throw")
        } catch TimeMachineExclusionError.commandFailed(let detail) {
            XCTAssertEqual(detail, "tmutil exited with status 3.")
        }
    }

    func testAHungTmutilIsTerminatedAtTheTimeout() async throws {
        // The Settings toggle stays disabled while this runs, so the call has to return.
        let tmutil = try await FakeExecutable.hanging()
        defer { tmutil.remove() }
        let timeout: Duration = .milliseconds(500)
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            try await TimeMachineExclusion(tmutilPath: tmutil.path, timeout: timeout)
                .update(dataPath, includeInBackups: false)
            XCTFail("a tmutil that outlives the timeout must throw")
        } catch TimeMachineExclusionError.timedOut(let reported) {
            XCTAssertEqual(reported, timeout)
        }

        XCTAssertLessThan(clock.now - startedAt, .milliseconds(1500))
        let stillRunning = try await tmutil.isRunning()
        XCTAssertFalse(stillRunning, "tmutil must be reaped before the error propagates")
    }
}
