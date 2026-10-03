import Foundation
import ProcessSupportTesting
import XCTest

@testable import ArcBox

final class DockerContextManagerTests: XCTestCase {
    func testContextInspectionKeepsWarningsOutOfJSON() async throws {
        let docker = try await FakeExecutable(
            """
            #!/bin/sh
            echo 'Docker CLI warning' >&2
            echo '{"Current":true,"DockerEndpoint":"unix:///Users/test/.orbstack/run/docker.sock","Name":"orbstack"}'

            """)
        defer { docker.remove() }

        let contexts = try await DockerContextManager.readDockerContexts(dockerPath: docker.path)

        XCTAssertEqual(
            contexts,
            [
                DockerContextDescription(
                    current: true,
                    dockerEndpoint: "unix:///Users/test/.orbstack/run/docker.sock",
                    name: "orbstack"
                )
            ]
        )
    }

    func testContextInspectionReportsCLIFailures() async throws {
        for detail in ["permission denied", ""] {
            let docker = try await FakeExecutable.recordingArguments(exitingWith: 1, standardError: detail)
            defer { docker.remove() }

            do {
                _ = try await DockerContextManager.readDockerContexts(dockerPath: docker.path)
                XCTFail("A failed context inspection must throw.")
            } catch {
                XCTAssertEqual(
                    error.localizedDescription,
                    detail.isEmpty ? "Docker context inspection failed." : detail
                )
            }
        }
    }

    func testContextInspectionReapsATerminationIgnoringCLIOnTimeout() async throws {
        let docker = try await FakeExecutable.ignoringTermination()
        defer { docker.remove() }
        let task = Task { try await DockerContextManager.readDockerContexts(dockerPath: docker.path) }
        defer { task.cancel() }
        let executed = try await docker.waitUntilExecuted()
        XCTAssertTrue(executed, "The CLI must install its SIGTERM handler before the deadline.")
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            _ = try await task.value
            XCTFail("A context inspection that exceeds its deadline must throw.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Docker context inspection timed out.")
        }

        let stillRunning = try await docker.isRunning()
        XCTAssertFalse(stillRunning, "The CLI must be reaped before the timeout propagates.")
        XCTAssertLessThan(clock.now - startedAt, .seconds(15))
    }

    func testContextInspectionPreservesCancellationAndReapsTheCLI() async throws {
        let docker = try await FakeExecutable.ignoringTermination()
        defer { docker.remove() }
        let task = Task {
            try await DockerContextManager.readDockerContexts(dockerPath: docker.path, timeout: .seconds(30))
        }
        defer { task.cancel() }
        let executed = try await docker.waitUntilExecuted()
        XCTAssertTrue(executed, "The CLI must install its SIGTERM handler before cancellation.")
        let clock = ContinuousClock()
        let startedAt = clock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled context inspection must throw.")
        } catch is CancellationError {
        }

        let stillRunning = try await docker.isRunning()
        XCTAssertFalse(stillRunning, "The CLI must be reaped before cancellation propagates.")
        XCTAssertLessThan(clock.now - startedAt, .seconds(15))
    }

    func testContextInspectionDoesNotWaitForADescendantHoldingStderr() async throws {
        let docker = try await FakeExecutable(
            """
            #!/bin/bash
            (exec -a "$0-child" /bin/sleep 30) >/dev/null &

            """)
        defer {
            docker.killGrandchild()
            docker.remove()
        }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let contexts = try await DockerContextManager.readDockerContexts(dockerPath: docker.path)

        XCTAssertTrue(contexts.isEmpty)
        XCTAssertLessThan(clock.now - startedAt, .seconds(10))
        let descendantRunning = try await docker.grandchildIsRunning()
        XCTAssertTrue(descendantRunning, "The probe must return while the descendant still holds stderr.")
    }

    func testSelectsPreviousExternalContextAfterArcBoxBecomesCurrent() throws {
        let data = Data(
            """
            {"Current":true,"DockerEndpoint":"unix:///Users/test/.arcbox/run/docker.sock","Name":"arcbox"}
            {"Current":false,"DockerEndpoint":"unix:///var/run/docker.sock","Name":"default"}
            {"Current":false,"DockerEndpoint":"unix:///Users/test/.orbstack/run/docker.sock","Name":"orbstack"}
            """.utf8
        )

        let source = try DockerContextManager.selectMigrationSource(
            from: try DockerContextManager.decodeDockerContexts(data),
            previousContext: "orbstack",
            homeDirectory: "/Users/test",
            socketExists: { $0 == "/Users/test/.orbstack/run/docker.sock" }
        )

        XCTAssertEqual(
            source,
            DockerMigrationSource(
                kind: .orbStack,
                contextName: "orbstack",
                socketPath: "/Users/test/.orbstack/run/docker.sock"
            )
        )
    }

    func testRejectsMalformedContextOutput() {
        XCTAssertThrowsError(
            try DockerContextManager.decodeDockerContexts(
                Data("{not-json}\n".utf8)
            )
        )
    }

    func testIgnoresDefaultRemoteAndStaleContexts() {
        let contexts = [
            DockerContextDescription(
                current: true,
                dockerEndpoint: "unix:///var/run/docker.sock",
                name: "default"
            ),
            DockerContextDescription(
                current: false,
                dockerEndpoint: "ssh://docker.example.com",
                name: "remote"
            ),
            DockerContextDescription(
                current: false,
                dockerEndpoint: "unix:///Users/test/.docker/run/docker.sock",
                name: "desktop-linux"
            ),
        ]

        XCTAssertNil(
            try DockerContextManager.selectMigrationSource(
                from: contexts,
                previousContext: nil,
                homeDirectory: "/Users/test",
                socketExists: { _ in false }
            )
        )
    }

    func testRejectsAmbiguousExternalContexts() {
        let contexts = [
            DockerContextDescription(
                current: false,
                dockerEndpoint: "unix:///Users/test/.docker/run/docker.sock",
                name: "desktop-linux"
            ),
            DockerContextDescription(
                current: false,
                dockerEndpoint: "unix:///Users/test/.orbstack/run/docker.sock",
                name: "orbstack"
            ),
        ]

        XCTAssertThrowsError(
            try DockerContextManager.selectMigrationSource(
                from: contexts,
                previousContext: nil,
                homeDirectory: "/Users/test",
                socketExists: { _ in true }
            )
        )
    }
}
