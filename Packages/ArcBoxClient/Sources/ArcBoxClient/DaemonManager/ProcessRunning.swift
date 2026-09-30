import Foundation

/// The child was still running when the caller's time limit elapsed. It has been terminated
/// and reaped by the time this error propagates.
struct ProcessTimedOut: Error {}

/// Runs `process` to completion. Cancellation terminates the child and still waits for it.
func runCancellableProcess(_ process: Process) async throws {
    try await process.runUntilExit()
}

/// Runs `process` and returns everything it wrote to standard output.
///
/// The read runs alongside the wait, so a child that writes more than the pipe holds still
/// exits. When `timeout` elapses first, or the caller is cancelled, the child is terminated
/// and reaped before the error propagates.
func runCapturingStandardOutput(_ process: Process, timeout: Duration) async throws -> Data {
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
    /// leaving the waiter parked forever after the child is gone (reproduced 2026-10-01 with
    /// six concurrent children in the first three rounds of a stress loop).
    ///
    /// Cancellation terminates the child and still waits for the exit, so the child is reaped
    /// before `CancellationError` propagates.
    func runUntilExit() async throws {
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
    func readToEndOfFile() async -> Data {
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
