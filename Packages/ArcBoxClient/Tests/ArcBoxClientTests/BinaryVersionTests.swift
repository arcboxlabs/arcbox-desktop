import Foundation
import ProcessSupport
import ProcessSupportTesting
import Testing

@testable import ArcBoxClient

/// How long a new task needs to get onto the main actor right now.
private func mainActorLatency() async -> Duration {
    let clock = ContinuousClock()
    let requestedAt = clock.now
    return await Task { @MainActor in clock.now - requestedAt }.value
}

struct BinaryVersionTests {
    @Test func returnsTheTrimmedVersionLineWithoutBlockingTheMainActor() async throws {
        let fake = try await FakeExecutable("#!/bin/sh\nsleep 0.5\necho 'arcbox-helper 9.9.9'\n")
        defer { fake.remove() }

        // From the main actor, as `installHelper` calls it.
        let version = Task { @MainActor in try await binaryVersion(fake.path) }
        try #require(try await fake.waitUntilRunning())
        let latency = await mainActorLatency()

        #expect(latency < .milliseconds(50), "main actor took \(latency) to schedule a task")
        let value = try await version.value
        #expect(value == "arcbox-helper 9.9.9")
    }

    @Test func returnsNilWhenTheBinaryWritesMoreThan64KiB() async throws {
        let fake = try await FakeExecutable.writingTwoMebibytes()
        defer { fake.remove() }

        let version = try await binaryVersion(fake.path)

        #expect(version == nil)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func returnsNilAfterTerminatingAChildThatOutlivesTheTimeout() async throws {
        let fake = try await FakeExecutable.hanging()
        defer { fake.remove() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let version = try await binaryVersion(fake.path, timeout: .seconds(1))

        let elapsed = clock.now - startedAt
        #expect(version == nil)
        // Generous for a loaded host; a child that outlived the timeout would show up at 30 s.
        #expect(elapsed < .seconds(3), "returned after \(elapsed)")
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func cancellationOutranksALimitTrippedBeforeIt() async throws {
        // The reader trips the limit and terminates the child, which ignores SIGTERM; the caller
        // is cancelled inside the 2 s kill grace. Cancellation must propagate — `installHelper`
        // reads a `nil` as "reinstall" — while the child is still reaped before it does.
        let fake = try await FakeExecutable.writingTwoMebibytesIgnoringTermination()
        defer { fake.remove() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let version = Task { try await binaryVersion(fake.path, timeout: .seconds(30)) }
        // Once `head` itself runs, `trap` has taken effect and the limit trips within
        // milliseconds; a SIGTERM that reached bash while it was still starting would end the
        // child at once and prove nothing.
        try #require(try await fake.waitUntilExecuted())
        try await Task.sleep(for: .milliseconds(200))
        version.cancel()

        await #expect(throws: CancellationError.self) { try await version.value }
        let elapsed = clock.now - startedAt
        #expect(elapsed > processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func returnsNilForAMissingOrFailingBinary() async throws {
        let missing = try await binaryVersion("/nonexistent/arcbox-helper")
        #expect(missing == nil)

        let failing = try await FakeExecutable("#!/bin/sh\necho 'arcbox-helper 9.9.9'\nexit 3\n")
        defer { failing.remove() }
        let failed = try await binaryVersion(failing.path)
        #expect(failed == nil)
    }

    @Test func cancellationTerminatesTheChildAndPropagates() async throws {
        let fake = try await FakeExecutable.hanging()
        defer { fake.remove() }

        let version = Task { try await binaryVersion(fake.path) }
        try #require(try await fake.waitUntilRunning())
        version.cancel()

        await #expect(throws: CancellationError.self) { try await version.value }
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }
}
