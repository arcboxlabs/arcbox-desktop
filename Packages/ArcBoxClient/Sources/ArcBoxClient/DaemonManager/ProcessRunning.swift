import Foundation

/// The child was still running when the caller's time limit elapsed. It has been terminated
/// and reaped by the time this error propagates.
struct ProcessTimedOut: Error {}

/// The child wrote more than the caller allowed. It has been terminated and reaped by the
/// time this error propagates.
struct ProcessOutputLimitExceeded: Error {
    let limit: Int
}

/// The exit of one child, armed before `run()` so it cannot be missed.
struct ProcessExit: Sendable {
    fileprivate let exited: AsyncStream<Void>
}

/// How long a terminated child gets to honour SIGTERM before it is killed.
let processTerminationGrace: Duration = .seconds(2)

/// Runs `process` to completion. Cancellation terminates the child and still waits for it.
func runCancellableProcess(_ process: Process) async throws {
    let exit = process.armExit()
    try process.run()
    try await process.waitForExit(exit)
}

/// Runs `process` and returns everything it wrote to standard output, up to `outputLimit`
/// bytes.
///
/// The read runs alongside the wait, so a child that writes more than the pipe holds still
/// exits. When `timeout` elapses first, the output exceeds `outputLimit`, or the caller is
/// cancelled, the child is terminated and reaped before the error propagates.
func runCapturingStandardOutput(
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
    func armExit() -> ProcessExit {
        let (exited, exit) = AsyncStream<Void>.makeStream()
        terminationHandler = { _ in exit.finish() }
        return ProcessExit(exited: exited)
    }

    /// Waits for the exit `armExit()` announced, without blocking a thread. Do not replace
    /// this with `waitUntilExit()` on a detached task: that call services the calling thread's
    /// run loop, and on a cooperative-pool thread the termination wake-up can fail to arrive,
    /// leaving the waiter parked forever after the child is gone (reproduced 2026-10-01 with
    /// six concurrent children in the first three rounds of a stress loop).
    ///
    /// Cancellation terminates the child, kills it if it still runs after
    /// `processTerminationGrace`, and still waits for the exit so the child is reaped before
    /// `CancellationError` propagates.
    func waitForExit(_ exit: ProcessExit) async throws {
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
    func readToEndOfFile(limit: Int) async throws -> Data {
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
