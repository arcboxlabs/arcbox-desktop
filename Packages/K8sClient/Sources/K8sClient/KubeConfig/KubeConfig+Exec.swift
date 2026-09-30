import Foundation

struct ExecConfig: Decodable, Sendable {
    let command: String
    let args: [String]
    let env: [ExecEnv]

    private enum CodingKeys: String, CodingKey {
        case command
        case args
        case env
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode(String.self, forKey: .command)
        self.args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        self.env = try container.decodeIfPresent([ExecEnv].self, forKey: .env) ?? []
    }
}

struct ExecEnv: Decodable, Sendable {
    let name: String
    let value: String
}

extension KubeConfig {
    // MARK: - Exec Credential Plugin

    /// Runs an exec credential plugin and returns the bearer token it prints.
    ///
    /// The wait and the stdout read run off the calling actor: the app resolves a kubeconfig
    /// from the main actor, and a plugin such as `aws eks get-token` takes seconds. A plugin
    /// still running after `timeout` is terminated.
    nonisolated static func runExecPlugin(
        command: String,
        args: [String],
        env: [ExecEnv],
        timeout: Duration = .seconds(15)
    ) async throws -> String {
        let process = Process()
        // A bare command name is resolved on PATH by env(1).
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }

        // Inherit current environment and overlay exec env vars
        var processEnv = ProcessInfo.processInfo.environment
        for variable in env {
            processEnv[variable.name] = variable.value
        }
        process.environment = processEnv
        process.standardError = FileHandle.nullDevice

        let output: Data
        do {
            output = try await runCapturingStandardOutput(process, timeout: timeout)
        } catch is ProcessTimedOut {
            throw KubeConfigError.execPluginFailed(
                "exec plugin timed out after \(timeout.components.seconds)s"
            )
        }

        guard process.terminationStatus == 0 else {
            throw KubeConfigError.execPluginFailed(
                "exec plugin exited with status \(process.terminationStatus)"
            )
        }

        let credential = try JSONDecoder().decode(ExecCredential.self, from: output)

        guard let token = credential.status?.token, !token.isEmpty else {
            throw KubeConfigError.execPluginFailed("exec plugin returned no token")
        }

        return token
    }
}

// MARK: - Process running

// Mirrors ArcBoxClient's `ProcessRunning.swift`; the two packages share no dependency.

/// The child was still running when the time limit elapsed. It has been terminated and reaped
/// by the time this error propagates.
private struct ProcessTimedOut: Error {}

/// Runs `process` and returns everything it wrote to standard output.
///
/// The read runs alongside the wait, so a child that writes more than the pipe holds still
/// exits. When `timeout` elapses first, or the caller is cancelled, the child is terminated
/// and reaped before the error propagates.
private func runCapturingStandardOutput(_ process: Process, timeout: Duration) async throws -> Data {
    let stdout = Pipe()
    process.standardOutput = stdout
    let output = Task { await stdout.fileHandleForReading.readToEndOfFile() }
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await process.runUntilExit() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw ProcessTimedOut()
        }
        defer { group.cancelAll() }
        try await group.next()
    }
    return await output.value
}

extension Process {
    /// Runs the child and returns once it has exited, without blocking a thread meanwhile.
    ///
    /// The exit arrives through `terminationHandler`, armed before `run()` because NSTask
    /// reports only terminations it observes after the handler is installed. Do not replace
    /// this with `waitUntilExit()` on a detached task: that call services the calling thread's
    /// run loop, and on a cooperative-pool thread the termination wake-up can fail to arrive,
    /// leaving the waiter parked forever after the child is gone.
    ///
    /// Cancellation terminates the child and still waits for the exit, so the child is reaped
    /// before `CancellationError` propagates.
    fileprivate func runUntilExit() async throws {
        try Task.checkCancellation()
        let (exited, exit) = AsyncStream<Void>.makeStream()
        terminationHandler = { _ in exit.finish() }
        try run()
        await withTaskCancellationHandler {
            // Iterating the stream from a cancelled task ends early, and the wait must outlive
            // the cancellation to observe the exit; an unstructured task inherits no cancellation.
            await Task { for await _ in exited {} }.value
        } onCancel: {
            if isRunning {
                terminate()
            }
        }
        try Task.checkCancellation()
    }
}

extension FileHandle {
    /// Reads until EOF without blocking a thread: chunks arrive on the readability callback.
    fileprivate func readToEndOfFile() async -> Data {
        let (chunks, feed) = AsyncStream<Data>.makeStream()
        readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                feed.finish()
            } else {
                feed.yield(chunk)
            }
        }
        var data = Data()
        for await chunk in chunks {
            data.append(chunk)
        }
        return data
    }
}
