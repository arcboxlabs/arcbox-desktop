import Foundation
import Testing

@testable import ArcBoxClient

/// An executable script standing in for a binary that answers `--version`.
private struct FakeBinary {
    /// Unique to this fake. The kernel runs the script as `<interpreter> <path> --version`, so a
    /// path carrying the marker puts it on the child's command line, where `pgrep -f` finds it.
    let marker: String
    let path: String
    private let directory: URL

    init(_ script: String) throws {
        let marker = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-version-\(marker)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("fake-\(marker)")
        try Data(script.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        self.marker = marker
        self.path = file.path
        self.directory = directory
    }

    /// Never exits on its own. `exec -a` keeps the marker as the sleep's `argv[0]`, and because
    /// nothing is forked, SIGTERM to the child leaves no orphan holding the stdout pipe open.
    static func hanging() throws -> FakeBinary {
        try FakeBinary("#!/bin/bash\nexec -a \"$0\" /bin/sleep 30\n")
    }

    /// Like `hanging()`, but ignores SIGTERM: `trap '' TERM` sets the disposition the exec'd
    /// sleep inherits.
    static func ignoringTermination() throws -> FakeBinary {
        try FakeBinary("#!/bin/bash\ntrap '' TERM\nexec -a \"$0\" /bin/sleep 30\n")
    }

    /// Writes 2 MiB to stdout and exits.
    static func writingTwoMebibytes() throws -> FakeBinary {
        try FakeBinary("#!/bin/bash\nexec -a \"$0\" /usr/bin/head -c 2097152 /dev/zero\n")
    }

    /// Writes 2 MiB and ignores SIGTERM: once the reader stops at its limit the write blocks,
    /// and only SIGKILL ends the child.
    static func writingTwoMebibytesIgnoringTermination() throws -> FakeBinary {
        try FakeBinary("#!/bin/bash\ntrap '' TERM\nexec -a \"$0\" /usr/bin/head -c 2097152 /dev/zero\n")
    }

    /// Prints its version and exits, leaving behind a grandchild that inherited stdout and
    /// keeps the pipe open for 30 s. Its `argv[0]` is the marker plus `-child`.
    static func leavingAGrandchildOnStdout() throws -> FakeBinary {
        try FakeBinary(
            """
            #!/bin/bash
            (exec -a "$0-child" /bin/sleep 30) &
            echo 'arcbox-helper 9.9.9'

            """
        )
    }

    /// Like `leavingAGrandchildOnStdout()`, but waits for `release()` first, so the test — not
    /// bash's start-up time — decides when the child exits.
    static func leavingAGrandchildOnStdoutWhenReleased() throws -> FakeBinary {
        let fake = try FakeBinary(
            """
            #!/bin/bash
            read _ < "$(dirname "$0")/release"
            (exec -a "$0-child" /bin/sleep 30) &
            echo 'arcbox-helper 9.9.9'

            """
        )
        guard mkfifo(fake.releasePath, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return fake
    }

    /// Lets a `leavingAGrandchildOnStdoutWhenReleased()` fake continue. The write end is
    /// opened non-blocking: with no reader — the child is already gone — `open` fails with
    /// ENXIO and the test fails, where a blocking open would hang the test host for good.
    func release() throws {
        let fifo = open(releasePath, O_WRONLY | O_NONBLOCK)
        guard fifo >= 0 else { throw ReleaseFailed(code: errno) }
        defer { close(fifo) }
        var newline: UInt8 = 0x0A
        guard write(fifo, &newline, 1) == 1 else { throw ReleaseFailed(code: errno) }
    }

    struct ReleaseFailed: Error, CustomStringConvertible {
        let code: Int32

        var description: String {
            code == ENXIO
                ? "the child is already gone: nothing reads the release FIFO"
                : String(cString: strerror(code))
        }
    }

    private var releasePath: String {
        directory.appendingPathComponent("release").path
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Whether a process carrying the marker on its command line is alive.
    func isRunning() async throws -> Bool {
        try await pgrep(marker)
    }

    /// Whether the grandchild `leavingAGrandchildOnStdout()` forks is alive.
    func grandchildIsRunning() async throws -> Bool {
        try await pgrep("\(marker)-child")
    }

    /// Kills that grandchild; nothing in the code under test can, it is not in the child's
    /// process group. Synchronous and unwaited so that a `defer` registered before the
    /// assertions can call it: a failed assertion must not leave a 30 s sleeper behind.
    func killGrandchild() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-KILL", "-f", "\(marker)-child"]
        try? pkill.run()
    }

    /// Polls until the fake's own program runs, or two seconds pass. `exec -a "$0"` puts the
    /// path first on the command line, where the interpreter's `/bin/bash <path>` had it
    /// second — so this also means the script's `trap` has run.
    func waitUntilExecuted() async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while clock.now < deadline {
            if try await pgrep("^\(path)") { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Polls until the child shows up or two seconds pass; a fixed sleep raced the spawn.
    func waitUntilRunning() async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while clock.now < deadline {
            if try await isRunning() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func pgrep(_ pattern: String) async throws -> Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", pattern]
        pgrep.standardOutput = FileHandle.nullDevice
        try await runCancellableProcess(pgrep)
        return pgrep.terminationStatus == 0
    }
}

/// How long a new task needs to get onto the main actor right now.
private func mainActorLatency() async -> Duration {
    let clock = ContinuousClock()
    let requestedAt = clock.now
    return await Task { @MainActor in clock.now - requestedAt }.value
}

/// The descriptors this process holds open; `/dev/fd` lists them.
private func openFileDescriptorCount() throws -> Int {
    try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
}

struct BinaryVersionTests {
    @Test func returnsTheTrimmedVersionLineWithoutBlockingTheMainActor() async throws {
        let fake = try FakeBinary("#!/bin/sh\nsleep 0.5\necho 'arcbox-helper 9.9.9'\n")
        defer { fake.remove() }

        // From the main actor, as `installHelper` calls it.
        let version = Task { @MainActor in try await binaryVersion(fake.path) }
        try #require(try await fake.waitUntilRunning())
        let latency = await mainActorLatency()

        #expect(latency < .milliseconds(50), "main actor took \(latency) to schedule a task")
        let value = try await version.value
        #expect(value == "arcbox-helper 9.9.9")
    }

    @Test func readsOutputLargerThanThePipeBuffer() async throws {
        // ~220 KiB: a reader that waits for the exit first deadlocks against the 64 KiB pipe.
        let fake = try FakeBinary(
            """
            #!/bin/sh
            i=0
            while [ $i -lt 8000 ]; do echo 'arcbox-helper 9.9.9 padding'; i=$((i+1)); done

            """
        )
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)

        let output = try await runCapturingStandardOutput(process, timeout: .seconds(5), outputLimit: 1 << 20)

        let text = try #require(String(bytes: output, encoding: .utf8))
        let lines = text.split(separator: "\n")
        #expect(lines.count == 8000)
        #expect(lines.last == "arcbox-helper 9.9.9 padding")
        #expect(process.terminationStatus == 0)
    }

    @Test func returnsTheVersionWhenAGrandchildKeepsStdoutOpen() async throws {
        let fake = try FakeBinary.leavingAGrandchildOnStdout()
        defer { fake.remove() }
        defer { fake.killGrandchild() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        // The timeout is far away; the child's exit must end the call, not EOF.
        let version = try await binaryVersion(fake.path, timeout: .seconds(30))

        let elapsed = clock.now - startedAt
        #expect(version == "arcbox-helper 9.9.9")
        #expect(elapsed < .seconds(1), "returned after \(elapsed)")
        // The scenario is real only if the grandchild is still there holding the pipe.
        let grandchildAlive = try await fake.grandchildIsRunning()
        #expect(grandchildAlive, "the fake must leave a grandchild on stdout")
    }

    @Test func exitJustBeforeTheDeadlineIsNotATimeout() async throws {
        // The child exits 100 ms before the deadline and EOF never comes (a grandchild holds
        // stdout), so the deadline falls inside the 200 ms drain that follows the exit. A
        // timeout that kept racing through the drain reported this successful exit as a
        // timeout. The exit is released by the test rather than timed with `sleep`, because
        // bash alone takes 0.1–0.35 s to start.
        let fake = try FakeBinary.leavingAGrandchildOnStdoutWhenReleased()
        defer { fake.remove() }
        defer { fake.killGrandchild() }
        let timeout: Duration = .seconds(1)

        let version = Task { try await binaryVersion(fake.path, timeout: timeout) }
        try await Task.sleep(for: timeout - .milliseconds(100))
        try fake.release()

        let value = try await version.value
        #expect(value == "arcbox-helper 9.9.9")
    }

    @Test func returnsNilWhenTheBinaryWritesMoreThan64KiB() async throws {
        let fake = try FakeBinary.writingTwoMebibytes()
        defer { fake.remove() }

        let version = try await binaryVersion(fake.path)

        #expect(version == nil)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func outputBeyondTheLimitTerminatesTheChild() async throws {
        let fake = try FakeBinary.writingTwoMebibytes()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)

        await #expect(throws: ProcessOutputLimitExceeded.self) {
            try await runCapturingStandardOutput(process, timeout: .seconds(5), outputLimit: 1 << 20)
        }

        #expect(!process.isRunning)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func returnsNilAfterTerminatingAChildThatOutlivesTheTimeout() async throws {
        let fake = try FakeBinary.hanging()
        defer { fake.remove() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let version = try await binaryVersion(fake.path, timeout: .seconds(1))

        let elapsed = clock.now - startedAt
        #expect(version == nil)
        #expect(elapsed < .milliseconds(1500), "returned after \(elapsed)")
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func timeoutTerminatesAndReapsTheChild() async throws {
        let fake = try FakeBinary.hanging()
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

    @Test func limitTrippedBeforeTheTimeoutIsReportedAsTheLimit() async throws {
        // The reader trips the limit within milliseconds and terminates the child, which
        // ignores SIGTERM; the 1 s timeout then fires inside the 2 s kill grace. The limit is
        // the cause and must be the error, and the child is still reaped before it propagates.
        let fake = try FakeBinary.writingTwoMebibytesIgnoringTermination()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        let clock = ContinuousClock()
        let startedAt = clock.now

        await #expect(throws: ProcessOutputLimitExceeded.self) {
            try await runCapturingStandardOutput(process, timeout: .seconds(1), outputLimit: 1 << 20)
        }

        let elapsed = clock.now - startedAt
        #expect(elapsed > processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        #expect(elapsed < processTerminationGrace + .seconds(1), "returned after \(elapsed)")
        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }

    @Test func cancellationOutranksALimitTrippedBeforeIt() async throws {
        // The reader trips the limit and terminates the child, which ignores SIGTERM; the caller
        // is cancelled inside the 2 s kill grace. Cancellation is what the caller asked for and
        // must propagate — `installHelper` reads a `nil` as "reinstall" — while the child is
        // still reaped before it does.
        let fake = try FakeBinary.writingTwoMebibytesIgnoringTermination()
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

    @Test func killsAChildThatIgnoresSIGTERM() async throws {
        let fake = try FakeBinary.ignoringTermination()
        defer { fake.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fake.path)
        process.arguments = ["--version"]
        let timeout: Duration = .milliseconds(500)
        let clock = ContinuousClock()
        let startedAt = clock.now

        await #expect(throws: ProcessTimedOut.self) {
            try await runCapturingStandardOutput(process, timeout: timeout, outputLimit: 1 << 20)
        }

        let elapsed = clock.now - startedAt
        #expect(elapsed > timeout + processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        #expect(elapsed < timeout + processTerminationGrace + .milliseconds(500), "returned after \(elapsed)")
        #expect(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
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

    @Test func returnsNilForAMissingOrFailingBinary() async throws {
        let missing = try await binaryVersion("/nonexistent/arcbox-helper")
        #expect(missing == nil)

        let failing = try FakeBinary("#!/bin/sh\necho 'arcbox-helper 9.9.9'\nexit 3\n")
        defer { failing.remove() }
        let failed = try await binaryVersion(failing.path)
        #expect(failed == nil)
    }

    @Test func cancellationTerminatesTheChildAndPropagates() async throws {
        let fake = try FakeBinary.hanging()
        defer { fake.remove() }

        let version = Task { try await binaryVersion(fake.path) }
        try #require(try await fake.waitUntilRunning())
        version.cancel()

        await #expect(throws: CancellationError.self) { try await version.value }
        let stillRunning = try await fake.isRunning()
        #expect(!stillRunning)
    }
}
