import Foundation
import ProcessSupport
import ProcessSupportTesting
import Testing

/// The descriptors this process holds open; `/dev/fd` lists them.
private func openFileDescriptorCount() throws -> Int {
    try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
}

struct ProcessRunningTests {
    @Test func readsOutputLargerThanThePipeBuffer() async throws {
        // ~220 KiB: a reader that waits for the exit first deadlocks against the 64 KiB pipe.
        let fake = try await FakeExecutable(
            """
            #!/bin/sh
            i=0
            while [ $i -lt 8000 ]; do echo 'arcbox-helper 9.9.9 padding'; i=$((i+1)); done

            """
        )
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)

        // The deadline is a safety net here, not the subject: generous for a loaded host.
        let output = try await runCapturingStandardOutput(process, timeout: .seconds(30), outputLimit: 1 << 20)

        let text = try #require(String(bytes: output, encoding: .utf8))
        let lines = text.split(separator: "\n")
        #expect(lines.count == 8000)
        #expect(lines.last == "arcbox-helper 9.9.9 padding")
        #expect(process.terminationStatus == 0)
    }

    @Test func theChildsExitEndsTheCallWhenAGrandchildKeepsStdoutOpen() async throws {
        let fake = try await FakeExecutable.leavingAGrandchildOnStdout(printing: "hello")
        defer { fake.remove() }
        defer { fake.killGrandchild() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        let clock = ContinuousClock()
        let startedAt = clock.now

        // The timeout is far away; the child's exit must end the call, not EOF (the grandchild
        // holds the pipe for 30 s). Bash start-up alone is 0.1–0.35 s and more under a loaded
        // test host, so the bound only has to beat those two.
        let output = try await runCapturingStandardOutput(process, timeout: .seconds(30), outputLimit: 1 << 20)

        let elapsed = clock.now - startedAt
        #expect(output == Data("hello\n".utf8))
        #expect(elapsed < .seconds(5), "returned after \(elapsed)")
        // The scenario is real only if the grandchild is still there holding the pipe.
        let grandchildAlive = try await fake.grandchildIsRunning()
        #expect(grandchildAlive, "the fake must leave a grandchild on stdout")
    }

    @Test func exitJustBeforeTheDeadlineIsNotATimeout() async throws {
        // The child exits 150 ms before the deadline and EOF never comes (a grandchild holds
        // stdout), so the deadline falls inside the 200 ms drain that follows the exit. A
        // timeout that kept racing through the drain reported this successful exit as a
        // timeout. The exit is released by the test rather than timed with `sleep`, because
        // bash alone takes 0.1–0.35 s to start — and seconds on a loaded host, which is what
        // the 3 s deadline leaves room for: the child must be blocked in `read` by the release.
        let fake = try await FakeExecutable.leavingAGrandchildOnStdoutWhenReleased(printing: "hello")
        defer { fake.remove() }
        defer { fake.killGrandchild() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        let timeout: Duration = .seconds(3)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let run = Task { try await runCapturingStandardOutput(process, timeout: timeout, outputLimit: 1 << 20) }
        try #require(try await fake.waitUntilRunning())
        try await Task.sleep(until: startedAt + timeout - .milliseconds(150), clock: clock)
        try fake.release()

        let output = try await run.value
        #expect(output == Data("hello\n".utf8))
    }

    @Test func outputBeyondTheLimitTerminatesTheChild() async throws {
        let fake = try await FakeExecutable.writingTwoMebibytes()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)

        await #expect(throws: ProcessOutputLimitExceeded.self) {
            try await runCapturingStandardOutput(process, timeout: .seconds(30), outputLimit: 1 << 20)
        }

        #expect(!process.isRunning)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func timeoutTerminatesAndReapsTheChild() async throws {
        let fake = try await FakeExecutable.hanging()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        process.arguments = ["--version"]

        let run = Task {
            try await runCapturingStandardOutput(process, timeout: .milliseconds(500), outputLimit: 1 << 20)
        }
        try #require(try await fake.waitUntilRunning(), "the marker must find the child while it runs")

        await #expect(throws: ProcessTimedOut.self) { try await run.value }

        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
        let runningAfterTimeout = try await fake.isRunning()
        #expect(!runningAfterTimeout)
    }

    @Test func killsAChildThatIgnoresSIGTERM() async throws {
        // The script's `trap` must be in place when SIGTERM arrives at the deadline, or bash
        // just dies and proves nothing. The deadline is measured from the launch, so it cannot
        // wait for the trap; just under the grace leaves bash the most time a fixed deadline
        // can (Gatekeeper's first-launch cost is already paid by the fixture), and the
        // `#require` below names the precondition when a host still misses it.
        let fake = try await FakeExecutable.ignoringTermination()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        process.arguments = ["--version"]
        let timeout = processTerminationGrace - .milliseconds(100)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let run = Task { try await runCapturingStandardOutput(process, timeout: timeout, outputLimit: 1 << 20) }
        try #require(try await fake.waitUntilExecuted(), "the child must install its trap before the deadline")

        await #expect(throws: ProcessTimedOut.self) { try await run.value }

        let elapsed = clock.now - startedAt
        #expect(elapsed > timeout + processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        // Generous for a loaded host; a child that outlived the kill would show up at 30 s.
        #expect(elapsed < timeout + processTerminationGrace + .seconds(2), "returned after \(elapsed)")
        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func limitTrippedBeforeTheTimeoutIsReportedAsTheLimit() async throws {
        // The reader trips the limit within milliseconds of `yes` starting and terminates the
        // child, which ignores SIGTERM; the timeout then fires inside the 2 s kill grace. The
        // limit is the cause and must be the error, and the child is still reaped before it
        // propagates. The deadline must fall between the limit tripping and the kill, and both
        // are measured from the launch, so a fixed deadline cannot wait for `yes` to appear;
        // just under the grace gives it the most slack a fixed deadline can — bash may take up
        // to that long to start (Gatekeeper's first-launch cost is already paid by the fixture)
        // — and the `#require` below names the precondition when a host still misses it.
        let fake = try await FakeExecutable.writingContinuouslyIgnoringTermination()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        let timeout = processTerminationGrace - .milliseconds(100)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let run = Task { try await runCapturingStandardOutput(process, timeout: timeout, outputLimit: 1 << 20) }
        try #require(try await fake.waitUntilExecuted(), "`yes` must be running before the deadline")
        let executedAt = clock.now

        await #expect(throws: ProcessOutputLimitExceeded.self) { try await run.value }

        let elapsed = clock.now - startedAt
        #expect(elapsed > processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        // Measured from `yes` running, so a slow bash start does not count against it.
        let sinceExecuted = clock.now - executedAt
        #expect(sinceExecuted < processTerminationGrace + .seconds(1), "returned \(sinceExecuted) after the child ran")
        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func cancellationOutranksALimitTrippedBeforeIt() async throws {
        // The reader trips the limit and terminates the child, which ignores SIGTERM; the caller
        // is cancelled inside the 2 s kill grace. Cancellation is what the caller asked for and
        // must propagate, while the child is still reaped before it does.
        let fake = try await FakeExecutable.writingContinuouslyIgnoringTermination()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let run = Task { try await runCapturingStandardOutput(process, timeout: .seconds(30), outputLimit: 1 << 20) }
        // Once `yes` itself runs, `trap` has taken effect and the limit trips within
        // milliseconds; a SIGTERM that reached bash while it was still starting would end the
        // child at once and prove nothing.
        try #require(try await fake.waitUntilExecuted())
        try await Task.sleep(for: .milliseconds(200))
        run.cancel()

        await #expect(throws: CancellationError.self) { try await run.value }
        let elapsed = clock.now - startedAt
        #expect(elapsed > processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        #expect(!process.isRunning)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func failedLaunchLeavesNoReaderBehind() async throws {
        let before = try openFileDescriptorCount()

        for _ in 0..<40 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/nonexistent/arcbox-helper")
            await #expect(throws: (any Error).self) {
                try await runCapturingStandardOutput(process, timeout: .seconds(1), outputLimit: 1 << 20)
            }
        }

        // A reader started before the launch held both pipe ends per attempt (80 here).
        let leaked = try openFileDescriptorCount() - before
        #expect(leaked < 20, "\(leaked) descriptors left open by 40 failed launches")
    }

    @Test func cancellationTerminatesTheChildBeforePropagating() async throws {
        let fake = try await FakeExecutable.hanging()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)

        let run = Task { try await runCancellableProcess(process) }
        try #require(try await fake.waitUntilRunning())
        let clock = ContinuousClock()
        let cancelledAt = clock.now
        run.cancel()

        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(clock.now - cancelledAt < .seconds(1))
        #expect(!process.isRunning)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func timeoutOnAPlainRunTerminatesAndReapsTheChild() async throws {
        let fake = try await FakeExecutable.hanging()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        let clock = ContinuousClock()
        let startedAt = clock.now

        await #expect(throws: ProcessTimedOut.self) {
            try await runCancellableProcess(process, timeout: .milliseconds(500))
        }

        let elapsed = clock.now - startedAt
        #expect(elapsed < .seconds(3), "returned after \(elapsed)")
        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func capturesStandardErrorAlone() async throws {
        let fake = try await FakeExecutable("#!/bin/sh\necho out\necho err >&2\nexit 3\n")
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        process.standardOutput = FileHandle.nullDevice

        let output = try await runCapturingStandardError(process, timeout: .seconds(30), outputLimit: 1 << 20)

        #expect(output == Data("err\n".utf8))
        #expect(process.terminationStatus == 3)
    }

    @Test func timeoutErrorsDescribeThemselves() {
        #expect(
            ProcessTimedOut(timeout: .seconds(10)).errorDescription == "The process did not exit within 10 seconds.")
        #expect(ProcessOutputLimitExceeded(limit: 65536).errorDescription == "The process wrote more than 65536 bytes.")
    }
}
