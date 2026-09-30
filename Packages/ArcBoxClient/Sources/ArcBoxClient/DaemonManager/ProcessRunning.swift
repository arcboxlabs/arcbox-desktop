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

/// How long EOF may lag the child's exit before the read is cut short. A child that has
/// exited already closed its write end, so EOF follows at once; only a grandchild that
/// inherited stdout can still hold the pipe open, and the call does not wait for it.
let processOutputDrainGrace: Duration = .milliseconds(200)

/// Runs `process` to completion. Cancellation terminates the child and still waits for it.
func runCancellableProcess(_ process: Process) async throws {
    let exit = process.armExit()
    try process.run()
    try await process.waitForExit(exit)
}

/// What a child of the capture group reports back to it.
private enum ProcessEvent {
    case exited
    case outputEnded
    case drainExpired
}

/// Runs `process` and returns everything it wrote to standard output, up to `outputLimit`
/// bytes.
///
/// The read runs alongside the wait, so a child that writes more than the pipe holds still
/// exits, and the child's exit — not EOF — bounds the call: output arriving after the exit is
/// read for `processOutputDrainGrace`, then the read stops and the parent's read end is
/// closed. When `timeout` elapses first, the output exceeds `outputLimit`, or the caller is
/// cancelled, the child is terminated and reaped before the error propagates. A grandchild
/// that inherited stdout is neither waited for nor killed: `Process` offers no process group.
func runCapturingStandardOutput(
    _ process: Process,
    timeout: Duration,
    outputLimit: Int
) async throws -> Data {
    let stdout = Pipe()
    process.standardOutput = stdout
    let reader = stdout.fileHandleForReading
    let exit = process.armExit()
    // Nothing else starts before the launch succeeds: `run()` closes the parent's write end
    // only when it launches the child, so a reader armed earlier would wait for EOF forever.
    // For the same reason a failed launch closes the pipe itself, rather than holding both
    // descriptors until the autoreleased handles go away.
    do {
        try process.run()
    } catch {
        try? reader.close()
        try? stdout.fileHandleForWriting.close()
        throw error
    }
    defer { try? reader.close() }

    // The reader is its own task so that it can be cancelled on its own once the child is
    // gone. The group still cannot finish before it does: the child awaiting it cancels it
    // when the group is torn down.
    let capture = Task { try await reader.readToEndOfFile(limit: outputLimit) }
    try await withThrowingTaskGroup(of: ProcessEvent.self) { group in
        group.addTask {
            try await process.waitForExit(exit)
            return .exited
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw ProcessTimedOut()
        }
        group.addTask {
            try await withTaskCancellationHandler {
                _ = try await capture.value
            } onCancel: {
                capture.cancel()
            }
            return .outputEnded
        }
        defer { group.cancelAll() }
        var exited = false
        var outputEnded = false
        while !(exited && outputEnded) {
            guard let event = try await group.next() else { break }
            switch event {
            case .exited:
                exited = true
                if !outputEnded {
                    group.addTask {
                        try await Task.sleep(for: processOutputDrainGrace)
                        capture.cancel()
                        return .drainExpired
                    }
                }
            case .outputEnded:
                outputEnded = true
            case .drainExpired:
                break
            }
        }
    }
    return try await capture.value
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
    /// arrived; cancellation stops it too and returns what has arrived so far.
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
