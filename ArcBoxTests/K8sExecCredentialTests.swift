import ProcessSupport
import ProcessSupportTesting
import XCTest

@testable import K8sClient

private let credentialJSON = """
    {"apiVersion":"client.authentication.k8s.io/v1beta1","kind":"ExecCredential","status":{"token":"tok-123"}}
    """

extension FakeExecutable {
    /// Prints a valid credential.
    fileprivate static func token() async throws -> FakeExecutable {
        try await FakeExecutable("#!/bin/sh\necho '\(credentialJSON)'\n")
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
    private func killGrandchildOnTeardown(of plugin: FakeExecutable) {
        addTeardownBlock {
            plugin.killGrandchild()
        }
    }

    // MARK: - runExecPlugin

    func testPluginTokenIsReturned() async throws {
        let plugin = try await FakeExecutable.token()
        defer { plugin.remove() }

        let token = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])

        XCTAssertEqual(token, "tok-123")
    }

    func testBareCommandResolvesOnThePathTheKubeconfigSets() async throws {
        let plugin = try await FakeExecutable(named: "fake-auth-plugin", "#!/bin/sh\necho '\(credentialJSON)'\n")
        defer { plugin.remove() }
        let name = URL(fileURLWithPath: plugin.path).lastPathComponent

        let token = try await KubeConfig.runExecPlugin(
            command: name, args: [], env: [ExecEnv(name: "PATH", value: plugin.directory.path)])

        XCTAssertEqual(token, "tok-123")
    }

    func testTokenIsReturnedWhenAGrandchildKeepsStdoutOpen() async throws {
        let plugin = try await FakeExecutable.leavingAGrandchildOnStdout(printing: credentialJSON)
        defer { plugin.remove() }
        killGrandchildOnTeardown(of: plugin)
        let clock = ContinuousClock()
        let startedAt = clock.now

        // The default 15 s timeout is far away; the plugin's exit must end the call, not EOF
        // (the grandchild holds the pipe for 30 s). Bash start-up alone is 0.1–0.35 s and
        // more under a loaded test host, so the bound only has to beat those two.
        let token = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])

        let elapsed = clock.now - startedAt
        XCTAssertEqual(token, "tok-123")
        XCTAssertLessThan(elapsed, .seconds(5), "returned after \(elapsed)")
        // The scenario is real only if the grandchild is still there holding the pipe.
        let grandchildAlive = try await plugin.grandchildIsRunning()
        XCTAssertTrue(grandchildAlive, "the fake must leave a grandchild on stdout")
    }

    func testExitJustBeforeTheDeadlineIsNotATimeout() async throws {
        // The plugin exits 150 ms before the deadline and EOF never comes (a grandchild holds
        // stdout), so the deadline falls inside the 200 ms drain that follows the exit. A
        // timeout that kept racing through the drain reported this successful exit as a
        // timeout. The exit is released by the test rather than timed with `sleep`, because
        // bash alone takes 0.1–0.35 s to start — and seconds on a loaded host, which is what
        // the 3 s deadline leaves room for: the plugin must be blocked in `read` by the release.
        let plugin = try await FakeExecutable.leavingAGrandchildOnStdoutWhenReleased(printing: credentialJSON)
        defer { plugin.remove() }
        killGrandchildOnTeardown(of: plugin)
        let timeout: Duration = .seconds(3)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let resolution = Task {
            try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: timeout)
        }
        let running = try await plugin.waitUntilRunning()
        XCTAssertTrue(running, "the plugin must be running before it is released")
        try await Task.sleep(until: startedAt + timeout - .milliseconds(150), clock: clock)
        try plugin.release()

        let token = try await resolution.value
        XCTAssertEqual(token, "tok-123")
    }

    func testStalledPluginIsTerminatedAtTheTimeoutWithoutBlockingTheMainActor() async throws {
        let plugin = try await FakeExecutable.hanging()
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
        // Generous for a loaded host; a plugin that outlived the timeout would show up at 30 s.
        XCTAssertLessThan(clock.now - startedAt, .seconds(3))
        let runningAfterTimeout = try await plugin.isRunning()
        XCTAssertFalse(runningAfterTimeout, "the plugin must be terminated")
    }

    func testLimitTrippedBeforeTheTimeoutIsReportedAsTheLimit() async throws {
        // The reader trips the limit within milliseconds of `head` starting and terminates the
        // plugin, which ignores SIGTERM; the timeout then fires inside the 2 s kill grace. The
        // limit is the cause and must be the error, and the plugin is still reaped before it
        // propagates. The deadline sits just under the grace so that bash may take up to that
        // long to start on a loaded host and the deadline still lands inside the grace.
        let plugin = try await FakeExecutable.writingTwoMebibytesIgnoringTermination()
        defer { plugin.remove() }
        let timeout = processTerminationGrace - .milliseconds(100)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let resolution = Task {
            try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: timeout)
        }
        let executed = try await plugin.waitUntilExecuted()
        XCTAssertTrue(executed, "`head` must be running before the deadline")
        let executedAt = clock.now

        do {
            _ = try await resolution.value
            XCTFail("2 MiB of output must be refused")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertEqual(message, "exec plugin wrote more than 1048576 bytes")
        }

        let elapsed = clock.now - startedAt
        XCTAssertGreaterThan(elapsed, processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        // Measured from `head` running, so a slow bash start does not count against it.
        let sinceExecuted = clock.now - executedAt
        XCTAssertLessThan(
            sinceExecuted, processTerminationGrace + .seconds(1), "returned \(sinceExecuted) after the plugin ran")
        let stillRunning = try await plugin.isRunning()
        XCTAssertFalse(stillRunning, "the plugin must be killed")
    }

    func testCancellationOutranksALimitTrippedBeforeIt() async throws {
        // The reader trips the limit and terminates the plugin, which ignores SIGTERM; the caller
        // is cancelled inside the 2 s kill grace. Cancellation is what the caller asked for and
        // must propagate, while the plugin is still reaped before it does.
        let plugin = try await FakeExecutable.writingTwoMebibytesIgnoringTermination()
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
        XCTAssertGreaterThan(elapsed, processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        let stillRunning = try await plugin.isRunning()
        XCTAssertFalse(stillRunning, "the plugin must be killed")
    }

    func testPluginIgnoringSIGTERMIsKilledAfterTheGrace() async throws {
        // The script's `trap` must be in place when SIGTERM arrives at the deadline, or bash
        // just dies and proves nothing; the deadline leaves bash most of the kill grace to
        // start on a loaded host.
        let plugin = try await FakeExecutable.ignoringTermination()
        defer { plugin.remove() }
        let timeout = processTerminationGrace - .milliseconds(100)
        let clock = ContinuousClock()
        let startedAt = clock.now

        let resolution = Task {
            try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [], timeout: timeout)
        }
        let executed = try await plugin.waitUntilExecuted()
        XCTAssertTrue(executed, "the plugin must install its trap before the deadline")

        do {
            _ = try await resolution.value
            XCTFail("a plugin that outlives the timeout must fail")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertTrue(message.contains("timed out"), message)
        }

        let elapsed = clock.now - startedAt
        XCTAssertGreaterThan(
            elapsed, timeout + processTerminationGrace, "SIGTERM was ignored, so the kill waits out the grace")
        // Generous for a loaded host; a plugin that outlived the kill would show up at 30 s.
        XCTAssertLessThan(elapsed, timeout + processTerminationGrace + .seconds(2), "returned after \(elapsed)")
        let stillRunning = try await plugin.isRunning()
        XCTAssertFalse(stillRunning, "the plugin must be killed")
    }

    func testPluginOutputBeyondTheLimitIsAnError() async throws {
        let plugin = try await FakeExecutable.writingTwoMebibytes()
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
        let plugin = try await FakeExecutable("#!/bin/sh\nexit 7\n")
        defer { plugin.remove() }

        do {
            _ = try await KubeConfig.runExecPlugin(command: plugin.path, args: [], env: [])
            XCTFail("a failing plugin must throw")
        } catch KubeConfigError.execPluginFailed(let message) {
            XCTAssertEqual(message, "exec plugin exited with status 7")
        }
    }

    func testMissingTokenIsReported() async throws {
        let plugin = try await FakeExecutable("#!/bin/sh\necho '{\"status\":{}}'\n")
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
        let plugin = try await FakeExecutable.token()
        defer { plugin.remove() }

        let config = try await KubeConfig.load(yaml: kubeconfig(execCommand: plugin.path))

        guard case .bearerToken(let token) = config.authMode else {
            return XCTFail("expected a bearer token, got \(config.authMode)")
        }
        XCTAssertEqual(token, "tok-123")
        XCTAssertNil(config.execPlugin)
    }
}
