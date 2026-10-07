import Foundation

/// An executable shell script standing in for a program the code under test launches.
///
/// Every fake carries a unique marker in its path. The kernel runs the script as
/// `<interpreter> <path> <arguments>`, so the marker sits on the child's command line, where
/// `pgrep -f` finds it — which is how `isRunning()` tells whether the child was reaped. The
/// scripts that keep running `exec -a "$0"` their final program so the marker stays its
/// `argv[0]`, and because nothing is forked, SIGTERM to the child leaves no orphan holding a
/// stdout pipe open.
///
/// Creating a fake is `async`: the first exec of a new executable file goes through
/// Gatekeeper's assessment in `syspolicyd` (`com.apple.syspolicy.exec`), ~0.5 s on an idle
/// host and many seconds when several test hosts create fixtures at once — a child that has
/// not started by its deadline looks exactly like a starved host. `init` therefore runs the
/// script once with `FAKE_EXECUTABLE_WARM_UP` set, which the guard it injects after the
/// shebang turns into an immediate exit, so the assessment is paid before the test's clock
/// starts and the second exec takes milliseconds.
public struct FakeExecutable: Sendable {
    public let marker: String
    public let path: String
    public let directory: URL

    private static let warmUpVariable = "FAKE_EXECUTABLE_WARM_UP"

    /// Writes `script` — which must start with a shebang — as an executable file named
    /// `<name>-<marker>` in a fresh temporary directory and runs it once (see above);
    /// `remove()` deletes the directory.
    public init(named name: String = "fake", _ script: String) async throws {
        guard script.hasPrefix("#!") else { throw NoShebang() }
        let marker = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-executable-\(marker)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(name)-\(marker)")
        let guarded = script.replacing(
            "\n", with: "\n[ -n \"$\(Self.warmUpVariable)\" ] && exit 0\n", maxReplacements: 1)
        try Data(guarded.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        self.marker = marker
        self.path = file.path
        self.directory = directory
        _ = try await run(file.path, [], environment: [Self.warmUpVariable: "1"])
    }

    public struct NoShebang: Error {}

    /// Never exits on its own.
    public static func hanging() async throws -> FakeExecutable {
        try await FakeExecutable("#!/bin/bash\nexec -a \"$0\" /bin/sleep 30\n")
    }

    /// Like `hanging()`, but ignores SIGTERM: `trap '' TERM` sets the disposition the exec'd
    /// sleep inherits.
    public static func ignoringTermination() async throws -> FakeExecutable {
        try await FakeExecutable("#!/bin/bash\ntrap '' TERM\nexec -a \"$0\" /bin/sleep 30\n")
    }

    /// Writes 2 MiB to stdout and exits.
    public static func writingTwoMebibytes() async throws -> FakeExecutable {
        try await FakeExecutable("#!/bin/bash\nexec -a \"$0\" /usr/bin/head -c 2097152 /dev/zero\n")
    }

    /// Writes continuously and ignores SIGTERM, so only SIGKILL ends the child after the limit.
    /// A finite writer can exit before the consumer checks output already queued by the reader.
    public static func writingContinuouslyIgnoringTermination() async throws -> FakeExecutable {
        try await FakeExecutable("#!/bin/bash\ntrap '' TERM\nexec -a \"$0\" /usr/bin/yes\n")
    }

    /// Prints `line` and exits, leaving behind a grandchild that inherited stdout and keeps
    /// the pipe open for 30 s. Its `argv[0]` is the marker plus `-child`.
    public static func leavingAGrandchildOnStdout(printing line: String) async throws -> FakeExecutable {
        try await FakeExecutable(
            """
            #!/bin/bash
            (exec -a "$0-child" /bin/sleep 30) &
            echo \(shellQuoted(line))

            """
        )
    }

    /// Like `leavingAGrandchildOnStdout(printing:)`, but waits for `release()` first, so the
    /// test — not bash's start-up time — decides when the child exits.
    public static func leavingAGrandchildOnStdoutWhenReleased(printing line: String) async throws -> FakeExecutable {
        let fake = try await FakeExecutable(
            """
            #!/bin/bash
            read _ < "$(dirname "$0")/release"
            (exec -a "$0-child" /bin/sleep 30) &
            echo \(shellQuoted(line))

            """
        )
        guard mkfifo(fake.releasePath, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return fake
    }

    /// Records its arguments for `recordedArguments()`, writes `standardError` to stderr, and
    /// exits with `status`.
    public static func recordingArguments(
        exitingWith status: Int32 = 0,
        standardError: String = ""
    ) async throws -> FakeExecutable {
        try await FakeExecutable(
            """
            #!/bin/sh
            printf '%s\\n' "$@" > "$(dirname "$0")/arguments"
            printf '%s' \(shellQuoted(standardError)) >&2
            exit \(status)

            """
        )
    }

    /// The arguments a `recordingArguments(exitingWith:standardError:)` fake was run with.
    public func recordedArguments() throws -> [String] {
        let recorded = try String(contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)
        return recorded.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Lets a `leavingAGrandchildOnStdoutWhenReleased(printing:)` fake continue. The write end
    /// is opened non-blocking: with no reader — the child has not reached `read` yet, or is
    /// already gone — `open` fails with ENXIO and the test fails, where a blocking open would
    /// hang the test host for good.
    public func release() throws {
        let fifo = open(releasePath, O_WRONLY | O_NONBLOCK)
        guard fifo >= 0 else { throw ReleaseFailed(code: errno) }
        defer { close(fifo) }
        var newline: UInt8 = 0x0A
        guard write(fifo, &newline, 1) == 1 else { throw ReleaseFailed(code: errno) }
    }

    public struct ReleaseFailed: Error, CustomStringConvertible {
        public let code: Int32

        public var description: String {
            code == ENXIO
                ? "nothing has the release FIFO open for reading: the child has not reached `read` yet, or is already gone"
                : String(cString: strerror(code))
        }
    }

    private var releasePath: String {
        directory.appendingPathComponent("release").path
    }

    public func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Whether a process carrying the marker on its command line is alive.
    public func isRunning() async throws -> Bool {
        try await pgrep(marker)
    }

    /// Whether the grandchild `leavingAGrandchildOnStdout(printing:)` forks is alive.
    public func grandchildIsRunning() async throws -> Bool {
        try await pgrep("\(marker)-child")
    }

    /// Kills that grandchild; nothing in the code under test can, it is not in the child's
    /// process group. Synchronous and unwaited so that a `defer` registered before the
    /// assertions can call it: a failed assertion must not leave a 30 s sleeper behind.
    public func killGrandchild() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-KILL", "-f", "\(marker)-child"]
        try? pkill.run()
    }

    /// Polls until the fake's own program runs, or `pollLimit` passes. `exec -a "$0"` puts the
    /// path first on the command line, where the interpreter's `/bin/bash <path>` had it
    /// second — so this also means the script's `trap` has run.
    public func waitUntilExecuted() async throws -> Bool {
        try await poll { try await pgrep("^\(path)") }
    }

    /// Polls until the child shows up or `pollLimit` passes; a fixed sleep raced the spawn.
    public func waitUntilRunning() async throws -> Bool {
        try await poll { try await isRunning() }
    }

    /// How long the polls above wait. A poll returns the moment the child appears, so a
    /// generous limit costs nothing on a healthy host and keeps a loaded one from proceeding
    /// against a child that is not there yet.
    private static let pollLimit: Duration = .seconds(10)

    /// `pgrep -f` reads every process's arguments. Several test hosts polling back to back
    /// (four concurrent `make test`s each run these suites) is a spawn storm that slows the
    /// very children being waited for, so the polls pause between attempts.
    private static let pollInterval: Duration = .milliseconds(100)

    private func poll(until condition: () async throws -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.pollLimit
        while clock.now < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: Self.pollInterval)
        }
        return false
    }

    private func pgrep(_ pattern: String) async throws -> Bool {
        try await run("/usr/bin/pgrep", ["-f", pattern]) == 0
    }

    /// Runs a tool to completion and returns its exit status. The wait rides
    /// `terminationHandler` rather than `waitUntilExit()`, whose run-loop wait can wedge a
    /// cooperative thread; it is spelled out here because this module stays independent of
    /// `ProcessSupport` (see the manifest).
    private func run(_ tool: String, _ arguments: [String], environment: [String: String]? = nil) async throws -> Int32
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardOutput = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return process.terminationStatus
    }

    /// `text` as one single-quoted shell word.
    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
