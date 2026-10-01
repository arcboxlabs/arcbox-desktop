import Foundation

/// The child was still running when the caller's time limit elapsed. It has been terminated
/// and reaped by the time this error propagates.
public struct ProcessTimedOut: LocalizedError {
    public let timeout: Duration

    public init(timeout: Duration) {
        self.timeout = timeout
    }

    public var errorDescription: String? {
        "The process did not exit within \(timeout.formatted(.units(allowed: [.seconds, .milliseconds], width: .wide)))."
    }
}

/// The child wrote more than the caller allowed. It has been terminated and reaped by the
/// time this error propagates.
public struct ProcessOutputLimitExceeded: LocalizedError {
    public let limit: Int

    public init(limit: Int) {
        self.limit = limit
    }

    public var errorDescription: String? {
        "The process wrote more than \(limit) bytes."
    }
}

/// How long EOF may lag the child's exit before the read is cut short. A child that has
/// exited already closed its write end, so EOF follows at once; only a grandchild that
/// inherited the pipe can still hold it open, and the call does not wait for it.
public let processOutputDrainGrace: Duration = .milliseconds(200)

/// Runs `process` to completion. Cancellation terminates the child and still waits for it;
/// so does `timeout`, which then surfaces as `ProcessTimedOut`.
public func runCancellableProcess(_ process: Process, timeout: Duration? = nil) async throws {
    let exit = process.armExit()
    try process.run()
    try await process.waitForExit(exit, timeout: timeout)
}

/// Runs `process` and returns everything it wrote to standard output, up to `outputLimit`
/// bytes.
///
/// The read runs alongside the wait, so a child that writes more than the pipe holds still
/// exits, and the child's exit — not EOF — bounds the call: `timeout` races the exit alone,
/// and output arriving after the exit is read for `processOutputDrainGrace`, then the read
/// stops and the parent's read end is closed. A grandchild that inherited stdout is neither
/// waited for nor killed: `Process` offers no process group.
///
/// When `timeout` elapses first, the output exceeds `outputLimit`, or the caller is cancelled,
/// the child is terminated and reaped before the error propagates. When more than one of
/// those happens, the error is the first of: `CancellationError` (what the caller asked for),
/// `ProcessOutputLimitExceeded` (the reader ended the child; a later timeout only saw it
/// refuse SIGTERM), `ProcessTimedOut`.
public func runCapturingStandardOutput(
    _ process: Process,
    timeout: Duration,
    outputLimit: Int
) async throws -> Data {
    try await runCapturing(\.standardOutput, of: process, timeout: timeout, outputLimit: outputLimit)
}

/// Runs `process` and returns everything it wrote to standard error, up to `outputLimit`
/// bytes, under the rules of `runCapturingStandardOutput(_:timeout:outputLimit:)`.
///
/// For a command whose standard output is noise — `tmutil`, `docker context create` — the
/// failure detail lives here; point `standardOutput` at `FileHandle.nullDevice` first.
public func runCapturingStandardError(
    _ process: Process,
    timeout: Duration,
    outputLimit: Int
) async throws -> Data {
    try await runCapturing(\.standardError, of: process, timeout: timeout, outputLimit: outputLimit)
}

private func runCapturing(
    _ stream: ReferenceWritableKeyPath<Process, Any?>,
    of process: Process,
    timeout: Duration,
    outputLimit: Int
) async throws -> Data {
    let pipe = Pipe()
    process[keyPath: stream] = pipe
    let reader = pipe.fileHandleForReading
    let exit = process.armExit()
    // Nothing else starts before the launch succeeds: `run()` closes the parent's write end
    // only when it launches the child, so a reader armed earlier would wait for EOF forever.
    // For the same reason a failed launch closes the pipe itself, rather than holding both
    // descriptors until the autoreleased handles go away.
    do {
        try process.run()
    } catch {
        try? reader.close()
        try? pipe.fileHandleForWriting.close()
        throw error
    }
    defer { try? reader.close() }

    // On the limit the reader ends the child itself, so the wait below observes the exit.
    let capture = Task {
        do {
            return try await reader.readToEndOfFile(limit: outputLimit)
        } catch let exceeded as ProcessOutputLimitExceeded {
            process.terminateEscalating()
            throw exceeded
        }
    }
    // The timeout races the exit and nothing else: a child that exits at the deadline has
    // succeeded, and the EOF drain below must not be mistaken for it still running.
    do {
        try await process.waitForExit(exit, timeout: timeout)
    } catch {
        capture.cancel()
        // The caller's cancellation is what it asked for, whatever else went wrong meanwhile.
        try Task.checkCancellation()
        // A limit the reader tripped first is the cause even when the timeout surfaced: the
        // reader had already ended the child, and the timeout only saw it refuse SIGTERM
        // until the kill.
        if case .failure(let exceeded as ProcessOutputLimitExceeded) = await capture.result {
            throw exceeded
        }
        throw error
    }
    // The child is gone; EOF gets `processOutputDrainGrace` and no longer.
    let drain = Task {
        try? await Task.sleep(for: processOutputDrainGrace)
        capture.cancel()
    }
    defer { drain.cancel() }
    let output = try await capture.value
    try Task.checkCancellation()
    return output
}
