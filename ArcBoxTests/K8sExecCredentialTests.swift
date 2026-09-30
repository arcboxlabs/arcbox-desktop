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

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Whether a process carrying the marker on its command line is alive.
    func isRunning() async throws -> Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", marker]
        pgrep.standardOutput = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pgrep.terminationHandler = { _ in continuation.resume() }
            do {
                try pgrep.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return pgrep.terminationStatus == 0
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
