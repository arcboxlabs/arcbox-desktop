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

    /// The most stdout an exec plugin may write. A credential is a few KiB of JSON.
    private static let execPluginOutputLimit = 1 << 20

    /// Runs an exec credential plugin and returns the bearer token it prints.
    ///
    /// The wait and the stdout read run off the calling actor: the app resolves a kubeconfig
    /// from the main actor, and a plugin such as `aws eks get-token` takes seconds. A plugin
    /// still running after `timeout`, or writing past `execPluginOutputLimit`, is terminated.
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
            output = try await runCapturingStandardOutput(
                process, timeout: timeout, outputLimit: execPluginOutputLimit)
        } catch is ProcessTimedOut {
            throw KubeConfigError.execPluginFailed(
                "exec plugin timed out after \(timeout.components.seconds)s"
            )
        } catch let exceeded as ProcessOutputLimitExceeded {
            throw KubeConfigError.execPluginFailed(
                "exec plugin wrote more than \(exceeded.limit) bytes"
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

/// The child wrote more than the caller allowed. It has been terminated and reaped by the
/// time this error propagates.
private struct ProcessOutputLimitExceeded: Error {
    let limit: Int
}

/// The exit of one child, armed before `run()` so it cannot be missed.
private struct ProcessExit: Sendable {
    fileprivate let exited: AsyncStream<Void>
}

/// How long a terminated child gets to honour SIGTERM before it is killed.
private let processTerminationGrace: Duration = .seconds(2)

/// Runs `process` and returns everything it wrote to standard output, up to `outputLimit`
/// bytes.
///
/// The read runs alongside the wait, so a child that writes more than the pipe holds still
/// exits. When `timeout` elapses first, the output exceeds `outputLimit`, or the caller is
/// cancelled, the child is terminated and reaped before the error propagates.
private func runCapturingStandardOutput(
    _ process: Process,
    timeout: Duration,
    outputLimit: Int
) async throws -> Data {
    let stdout = Pipe()
    process.standardOutput = stdout
    let exit = process.armExit()
    // Nothing else starts before the launch succeeds: `run()` closes the parent's write end
    // only when it launches the child, so a reader armed earlier would wait for EOF forever.
    // For the same reason a failed launch closes the pipe itself, rather than holding both
    // descriptors until the autoreleased handles go away.
    do {
        try process.run()
    } catch {
        try? stdout.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        throw error
    }
    return try await withThrowingTaskGroup(of: Data?.self) { group in
        group.addTask { try await stdout.fileHandleForReading.readToEndOfFile(limit: outputLimit) }
        group.addTask {
            try await process.waitForExit(exit)
            return nil
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw ProcessTimedOut()
        }
        defer { group.cancelAll() }
        // EOF and the exit land in either order; the status is valid only after the exit.
        var output: Data?
        var hasExited = false
        while output == nil || !hasExited {
            guard let result = try await group.next() else { break }
            if let result {
                output = result
            } else {
                hasExited = true
            }
        }
        return output ?? Data()
    }
}

extension Process {
    /// Arms `terminationHandler`. Call it before `run()`: NSTask reports only terminations it
    /// observes after the handler is installed.
    fileprivate func armExit() -> ProcessExit {
        let (exited, exit) = AsyncStream<Void>.makeStream()
        terminationHandler = { _ in exit.finish() }
        return ProcessExit(exited: exited)
    }

    /// Waits for the exit `armExit()` announced, without blocking a thread. Do not replace
    /// this with `waitUntilExit()` on a detached task: that call services the calling thread's
    /// run loop, and on a cooperative-pool thread the termination wake-up can fail to arrive,
    /// leaving the waiter parked forever after the child is gone.
    ///
    /// Cancellation terminates the child, kills it if it still runs after
    /// `processTerminationGrace`, and still waits for the exit so the child is reaped before
    /// `CancellationError` propagates.
    fileprivate func waitForExit(_ exit: ProcessExit) async throws {
        await withTaskCancellationHandler {
            // Iterating the stream from a cancelled task ends early, and the wait must outlive
            // the cancellation to observe the exit; an unstructured task inherits no cancellation.
            await Task { for await _ in exit.exited {} }.value
        } onCancel: {
            guard self.isRunning else { return }
            self.terminate()
            Task {
                try? await Task.sleep(for: processTerminationGrace)
                if self.isRunning {
                    kill(self.processIdentifier, SIGKILL)
                }
            }
        }
        try Task.checkCancellation()
    }
}

extension FileHandle {
    /// Reads until EOF without blocking a thread: chunks arrive on the readability callback.
    /// Stops reading and throws `ProcessOutputLimitExceeded` once more than `limit` bytes have
    /// arrived.
    fileprivate func readToEndOfFile(limit: Int) async throws -> Data {
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
        defer { readabilityHandler = nil }
        var data = Data()
        for await chunk in chunks {
            data.append(chunk)
            if data.count > limit {
                throw ProcessOutputLimitExceeded(limit: limit)
            }
        }
        return data
    }
}
