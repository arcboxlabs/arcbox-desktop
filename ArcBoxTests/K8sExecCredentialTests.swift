import XCTest

@testable import K8sClient

/// An executable script standing in for an exec credential plugin.
private struct FakePlugin {
    /// Unique to this fake. The kernel runs the script as `<interpreter> <path> ...`, so a path
    /// carrying the marker puts it on the child's command line, where `pgrep -f` finds it.
    let marker: String
    let path: String
    let directory: URL

    static let credentialJSON = """
        {"apiVersion":"client.authentication.k8s.io/v1beta1","kind":"ExecCredential","status":{"token":"tok-123"}}
        """

    init(named name: String = "plugin", _ script: String) throws {
        let marker = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("k8s-exec-\(marker)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(name)-\(marker)")
        try Data(script.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        self.marker = marker
        self.path = file.path
        self.directory = directory
    }

    /// Prints a valid credential.
    static func token() throws -> FakePlugin {
        try FakePlugin("#!/bin/sh\necho '\(credentialJSON)'\n")
    }

    /// Never exits on its own. `exec -a` keeps the marker as the sleep's `argv[0]`, and because
    /// nothing is forked, SIGTERM to the child leaves no orphan holding the stdout pipe open.
    static func stalled() throws -> FakePlugin {
        try FakePlugin("#!/bin/bash\nexec -a \"$0\" /bin/sleep 30\n")
    }

    /// Like `stalled()`, but ignores SIGTERM: `trap '' TERM` sets the disposition the exec'd
    /// sleep inherits.
    static func ignoringTermination() throws -> FakePlugin {
        try FakePlugin("#!/bin/bash\ntrap '' TERM\nexec -a \"$0\" /bin/sleep 30\n")
    }

    /// Writes 2 MiB to stdout and exits.
    static func writingTwoMebibytes() throws -> FakePlugin {
        try FakePlugin("#!/bin/bash\nexec -a \"$0\" /usr/bin/head -c 2097152 /dev/zero\n")
    }

    /// Writes 2 MiB and ignores SIGTERM: once the reader stops at its limit the write blocks,
    /// and only SIGKILL ends the plugin.
    static func writingTwoMebibytesIgnoringTermination() throws -> FakePlugin {
        try FakePlugin("#!/bin/bash\ntrap '' TERM\nexec -a \"$0\" /usr/bin/head -c 2097152 /dev/zero\n")
    }

    /// Prints a valid credential and exits, leaving behind a grandchild that inherited stdout
    /// and keeps the pipe open for 30 s. Its `argv[0]` is the marker plus `-child`.
    static func leavingAGrandchildOnStdout() throws -> FakePlugin {
        try FakePlugin(
            """
            #!/bin/bash
            (exec -a "$0-child" /bin/sleep 30) &
            echo '\(credentialJSON)'

            """
        )
    }

    /// Like `leavingAGrandchildOnStdout()`, but waits for `release()` first, so the test — not
    /// bash's start-up time — decides when the plugin exits.
    static func leavingAGrandchildOnStdoutWhenReleased() throws -> FakePlugin {
        let plugin = try FakePlugin(
            """
            #!/bin/bash
            read _ < "$(dirname "$0")/release"
            (exec -a "$0-child" /bin/sleep 30) &
            echo '\(credentialJSON)'

            """
        )
        guard mkfifo(plugin.releasePath, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return plugin
    }

    /// Lets a `leavingAGrandchildOnStdoutWhenReleased()` fake continue. The write end is
    /// opened non-blocking: with no reader — the plugin is already gone — `open` fails with
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
                ? "the plugin is already gone: nothing reads the release FIFO"
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
        try await run("/usr/bin/pgrep", ["-f", marker]) == 0
    }

    /// Whether the grandchild `leavingAGrandchildOnStdout()` forks is alive.
    func grandchildIsRunning() async throws -> Bool {
        try await run("/usr/bin/pgrep", ["-f", "\(marker)-child"]) == 0
    }

    /// Kills that grandchild; nothing in the code under test can, it is not in the child's
    /// process group.
    func killGrandchild() async throws {
        _ = try await run("/usr/bin/pkill", ["-KILL", "-f", "\(marker)-child"])
    }

    /// Polls until the fake's own program runs, or two seconds pass. `exec -a "$0"` puts the
    /// path first on the command line, where the interpreter's `/bin/bash <path>` had it
    /// second — so this also means the script's `trap` has run.
    func waitUntilExecuted() async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while clock.now < deadline {
            if try await run("/usr/bin/pgrep", ["-f", "^\(path)"]) == 0 { return true }
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

    /// Runs a tool to completion and returns its exit status, waiting on `terminationHandler`.
    private func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
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

@available(macOS 15.0, *)
final class K8sExecCredentialTests: XCTestCase {

    /// `KubeConfig+Exec.swift` kills a child that ignores SIGTERM this long after the timeout.
    private let terminationGrace: Duration = .seconds(2)

    private func kubeconfig(execCommand: String) -> String {
        """
        apiVersion: v1
        kind: Config
        current-context: eks
        clusters:
        - name: eks
          cluster:
            server: https://example.invalid:6443
            certificate-authority-data: \(Data("ca".utf8).base64EncodedString())
        contexts:
        - name: eks
          context:
            cluster: eks
            user: eks
        users:
        - name: eks
          user:
            exec:
              apiVersion: client.authentication.k8s.io/v1beta1
              command: \(execCommand)
              args: ["--flag"]
        """
    }

    /// Registers the grandchild's removal before any assertion can throw and leave a 30 s
    /// sleeper behind.
    private func killGrandchildOnTeardown(of plugin: FakePlugin) {
        addTeardownBlock {
            try await plugin.killGrandchild()
        }
    }

    // MARK: - runExecPlugin

    func testPluginTokenIsReturned() async throws {
        let plugin = try FakePlugin.token()
        defer { plugin.remove() }

        let token = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])

        XCTAssertEqual(token, "tok-123")
    }

    func testBareCommandResolvesOnThePathTheKubeconfigSets() async throws {
        let plugin = try FakePlugin(named: "fake-auth-plugin", "#!/bin/sh\necho '\(FakePlugin.credentialJSON)'\n")
        defer { plugin.remove() }
        let name = URL(fileURLWithPath: plugin.path).lastPathComponent

        let token = try await KubeConfig.runExecPlugin(
            command: name, args: [], env: [ExecEnv(name: "PATH", value: plugin.directory.path)])

        XCTAssertEqual(token, "tok-123")
    }

    func testTokenIsReturnedWhenAGrandchildKeepsStdoutOpen() async throws {
        let plugin = try FakePlugin.leavingAGrandchildOnStdout()
        defer { plugin.remove() }
        killGrandchildOnTeardown(of: plugin)
        let clock = ContinuousClock()
        let startedAt = clock.now

        // The default 15 s timeout is far away; the plugin's exit must end the call, not EOF.
        let token = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])

        let elapsed = clock.now - startedAt
        XCTAssertEqual(token, "tok-123")
        XCTAssertLessThan(elapsed, .seconds(1), "returned after \(elapsed)")
        // The scenario is real only if the grandchild is still there holding the pipe.
        let grandchildAlive = try await plugin.grandchildIsRunning()
        XCTAssertTrue(grandchildAlive, "the fake must leave a grandchild on stdout")
    }

    func testExitJustBeforeTheDeadlineIsNotATimeout() async throws {
        // The plugin exits 100 ms before the deadline and EOF never comes (a grandchild holds
        // stdout), so the deadline falls inside the 200 ms drain that follows the exit. A
        // timeout that kept racing through the drain reported this successful exit as a
        // timeout. The exit is released by the test rather than timed with `sleep`, because
        // bash alone takes 0.1–0.35 s to start.
        let plugin = try FakePlugin.leavingAGrandchildOnStdoutWhenReleased()
        defer { plugin.remove() }
        killGrandchildOnTeardown(of: plugin)
        let timeout: Duration = .seconds(1)

        let resolution = Task {
            try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: timeout)
        }
        try await Task.sleep(for: timeout - .milliseconds(100))
        try plugin.release()

        let token = try await resolution.value
        XCTAssertEqual(token, "tok-123")
    }

    func testStalledPluginIsTerminatedAtTheTimeoutWithoutBlockingTheMainActor() async throws {
        let plugin = try FakePlugin.stalled()
        defer { plugin.remove() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        // From the main actor, as `KubernetesState` resolves its client.
        let resolution = Task { @MainActor in
            try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: .seconds(1))
        }
        let runningBeforeTimeout = try await plugin.waitUntilRunning()
        XCTAssertTrue(runningBeforeTimeout, "the marker must find the plugin while it runs")
        let latency = await mainActorLatency()
        XCTAssertLessThan(latency, .milliseconds(50), "main actor took \(latency) to schedule a task")

        do {
            _ = try await resolution.value
            XCTFail("a plugin sleeping past the timeout must fail")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertTrue(message.contains("timed out"), message)
        }
        XCTAssertLessThan(clock.now - startedAt, .milliseconds(1500))
        let runningAfterTimeout = try await plugin.isRunning()
        XCTAssertFalse(runningAfterTimeout, "the plugin must be terminated")
    }

    func testLimitTrippedBeforeTheTimeoutIsReportedAsTheLimit() async throws {
        // The reader trips the limit within milliseconds and terminates the plugin, which
        // ignores SIGTERM; the 1 s timeout then fires inside the 2 s kill grace. The limit is
        // the cause and must be the error, and the plugin is still reaped before it propagates.
        let plugin = try FakePlugin.writingTwoMebibytesIgnoringTermination()
        defer { plugin.remove() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            _ = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: .seconds(1))
            XCTFail("2 MiB of output must be refused")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertEqual(message, "exec plugin wrote more than 1048576 bytes")
        }

        let elapsed = clock.now - startedAt
        XCTAssertGreaterThan(elapsed, terminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        XCTAssertLessThan(elapsed, terminationGrace + .seconds(1), "returned after \(elapsed)")
        let stillRunning = try await plugin.isRunning()
        XCTAssertFalse(stillRunning, "the plugin must be killed")
    }

    func testCancellationOutranksALimitTrippedBeforeIt() async throws {
        // The reader trips the limit and terminates the plugin, which ignores SIGTERM; the caller
        // is cancelled inside the 2 s kill grace. Cancellation is what the caller asked for and
        // must propagate, while the plugin is still reaped before it does.
        let plugin = try FakePlugin.writingTwoMebibytesIgnoringTermination()
        defer { plugin.remove() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let resolution = Task {
            try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: .seconds(30))
        }
        // Once `head` itself runs, `trap` has taken effect and the limit trips within
        // milliseconds; a SIGTERM that reached bash while it was still starting would end the
        // plugin at once and prove nothing.
        let executed = try await plugin.waitUntilExecuted()
        XCTAssertTrue(executed, "the fake's own program must be running")
        try await Task.sleep(for: .milliseconds(200))
        resolution.cancel()

        do {
            _ = try await resolution.value
            XCTFail("a cancelled resolution must throw")
        } catch is CancellationError {
        }
        let elapsed = clock.now - startedAt
        XCTAssertGreaterThan(elapsed, terminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        let stillRunning = try await plugin.isRunning()
        XCTAssertFalse(stillRunning, "the plugin must be killed")
    }

    func testPluginIgnoringSIGTERMIsKilledAfterTheGrace() async throws {
        let plugin = try FakePlugin.ignoringTermination()
        defer { plugin.remove() }
        let timeout: Duration = .seconds(1)
        let clock = ContinuousClock()
        let startedAt = clock.now

        do {
            _ = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: timeout)
            XCTFail("a plugin that outlives the timeout must fail")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertTrue(message.contains("timed out"), message)
        }

        let elapsed = clock.now - startedAt
        XCTAssertGreaterThan(
            elapsed, timeout + terminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        XCTAssertLessThan(elapsed, timeout + terminationGrace + .milliseconds(500), "returned after \(elapsed)")
        let stillRunning = try await plugin.isRunning()
        XCTAssertFalse(stillRunning, "the plugin must be killed")
    }

    func testPluginOutputBeyondTheLimitIsAnError() async throws {
        let plugin = try FakePlugin.writingTwoMebibytes()
        defer { plugin.remove() }

        do {
            _ = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])
            XCTFail("2 MiB of output must be refused")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertEqual(message, "exec plugin wrote more than 1048576 bytes")
        }
        let stillRunning = try await plugin.isRunning()
        XCTAssertFalse(stillRunning, "the plugin must be terminated")
    }

    func testNonZeroExitReportsTheStatus() async throws {
        let plugin = try FakePlugin("#!/bin/sh\nexit 7\n")
        defer { plugin.remove() }

        do {
            _ = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])
            XCTFail("a failing plugin must throw")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertEqual(message, "exec plugin exited with status 7")
        }
    }

    func testMissingTokenIsReported() async throws {
        let plugin = try FakePlugin("#!/bin/sh\necho '{\"status\":{}}'\n")
        defer { plugin.remove() }

        do {
            _ = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])
            XCTFail("a credential without a token must throw")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertEqual(message, "exec plugin returned no token")
        }
    }

    // MARK: - KubeConfig

    func testParsingRunsNoPlugin() throws {
        let config = try KubeConfig(yaml: kubeconfig(execCommand: "/nonexistent/plugin"))

        guard case .execPlugin = config.authMode else {
            return XCTFail("expected .execPlugin, got \(config.authMode)")
        }
        XCTAssertEqual(config.execPlugin?.command, "/nonexistent/plugin")
        XCTAssertEqual(config.execPlugin?.args, ["--flag"])
        XCTAssertNil(config.clientCertificateData)
    }

    func testTheClientRefusesAnUnresolvedConfig() throws {
        let config = try KubeConfig(yaml: kubeconfig(execCommand: "/nonexistent/plugin"))

        XCTAssertThrowsError(try K8sClient(config: config)) { error in
            guard case KubeConfigError.unresolvedExecPlugin = error else {
                return XCTFail("expected unresolvedExecPlugin, got \(error)")
            }
        }
    }

    func testResolvingCredentialsSurfacesTheMissingPlugin() async throws {
        let config = try KubeConfig(yaml: kubeconfig(execCommand: "/nonexistent/plugin"))

        do {
            _ = try await config.resolvingCredentials()
            XCTFail("a missing plugin must fail at resolution, not at parse time")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain, "\(error)")
        }
    }

    func testMissingPluginLeavesNoReaderBehind() async throws {
        let config = try KubeConfig(yaml: kubeconfig(execCommand: "/nonexistent/plugin"))
        let before = try openFileDescriptorCount()

        for _ in 0..<40 {
            do {
                _ = try await config.resolvingCredentials()
                XCTFail("a missing plugin must fail")
            } catch {}
        }

        // A reader started before the launch held both pipe ends per attempt (80 here).
        let leaked = try openFileDescriptorCount() - before
        XCTAssertLessThan(leaked, 20, "\(leaked) descriptors left open by 40 failed launches")
    }

    func testLoadResolvesTheToken() async throws {
        let plugin = try FakePlugin.token()
        defer { plugin.remove() }

        let config = try await KubeConfig.load(yaml: kubeconfig(execCommand: plugin.path))

        guard case .bearerToken(let token) = config.authMode else {
            return XCTFail("expected a bearer token, got \(config.authMode)")
        }
        XCTAssertEqual(token, "tok-123")
        XCTAssertNil(config.execPlugin)
    }
}
