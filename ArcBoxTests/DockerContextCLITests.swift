import ProcessSupportTesting
import XCTest

@testable import ArcBox

final class DockerContextCLITests: XCTestCase {
    private func createArcBoxContext(with docker: FakeExecutable, timeout: Duration = .seconds(10)) async throws {
        try await DockerContextCLI(dockerPath: docker.path, timeout: timeout).createContext(
            named: "arcbox", host: "unix:///tmp/arcbox/docker.sock", description: "ArcBox Desktop")
    }

    func testCreatesTheContextForTheSocket() async throws {
        let docker = try FakeExecutable.recordingArguments()
        defer { docker.remove() }

        try await createArcBoxContext(with: docker)

        XCTAssertEqual(
            try docker.recordedArguments(),
            [
                "context", "create", "arcbox",
                "--docker", "host=unix:///tmp/arcbox/docker.sock",
                "--description", "ArcBox Desktop",
            ])
    }

    func testAnExistingContextIsNotAFailure() async throws {
        let docker = try FakeExecutable.recordingArguments(
            exitingWith: 1, standardError: "context \"arcbox\" already exists\n")
        defer { docker.remove() }

        try await createArcBoxContext(with: docker)
    }

    func testFailureReportsTheCLIsStderr() async throws {
        let docker = try FakeExecutable.recordingArguments(
            exitingWith: 1, standardError: "open /Users/me/.docker/contexts/meta: permission denied\n")
        defer { docker.remove() }

        do {
            try await createArcBoxContext(with: docker)
            XCTFail("a failing docker context create must throw")
        } catch DockerContextCLIError.commandFailed(let detail) {
            XCTAssertEqual(detail, "open /Users/me/.docker/contexts/meta: permission denied")
        }
    }

    func testASilentFailureReportsTheExitStatus() async throws {
        let docker = try FakeExecutable.recordingArguments(exitingWith: 2)
        defer { docker.remove() }

        do {
            try await createArcBoxContext(with: docker)
            XCTFail("a failing docker context create must throw")
        } catch DockerContextCLIError.commandFailed(let detail) {
            XCTAssertEqual(detail, "exit status 2")
        }
    }

    func testAHungCLIIsTerminatedAtTheTimeout() async throws {
        let docker = try FakeExecutable.hanging()
        defer { docker.remove() }
        let timeout: Duration = .milliseconds(500)
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            try await createArcBoxContext(with: docker, timeout: timeout)
            XCTFail("a docker CLI that outlives the timeout must throw")
        } catch DockerContextCLIError.timedOut(let reported) {
            XCTAssertEqual(reported, timeout)
        }

        XCTAssertLessThan(clock.now - startedAt, .milliseconds(1500))
        let stillRunning = try await docker.isRunning()
        XCTAssertFalse(stillRunning, "the docker CLI must be reaped before the error propagates")
    }
}
