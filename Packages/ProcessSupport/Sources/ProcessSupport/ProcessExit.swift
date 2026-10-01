import Foundation

/// The exit of one child, armed before `run()` so it cannot be missed.
public struct ProcessExit: Sendable {
    fileprivate let exited: AsyncStream<Void>
}

/// How long a terminated child gets to honour SIGTERM before it is killed. Two seconds covers
/// a CLI flushing its output and removing a temporary file; a child still running after that
/// is not going to exit on its own.
public let processTerminationGrace: Duration = .seconds(2)

extension Process {
    /// Arms `terminationHandler`. Call it before `run()`: NSTask reports only terminations it
    /// observes after the handler is installed.
    public func armExit() -> ProcessExit {
        let (exited, exit) = AsyncStream<Void>.makeStream()
        terminationHandler = { _ in exit.finish() }
        return ProcessExit(exited: exited)
    }

    /// Waits for the exit `armExit()` announced, without blocking a thread.
    ///
    /// Do not replace this with `waitUntilExit()` on a detached task. That call services the
    /// calling thread's run loop, and on a Swift-concurrency cooperative thread (`Task.detached`
    /// included) the termination wake-up can fail to arrive: the waiter stays parked in
    /// `-[NSConcreteTask waitUntilExit] → CFRunLoopRun → mach_msg2_trap` after the child is
    /// gone. Reproduced deterministically on 2026-10-01 with six concurrent children terminated
    /// at 300 ms — wedged in round 3 every time, where this `terminationHandler` design ran 320
    /// children clean.
    ///
    /// Cancellation terminates the child (`terminateEscalating()`) and still waits for the
    /// exit, so the child is reaped before `CancellationError` propagates.
    public func waitForExit(_ exit: ProcessExit) async throws {
        await withTaskCancellationHandler {
            // Iterating the stream from a cancelled task ends early, and the wait must outlive
            // the cancellation to observe the exit; an unstructured task inherits no cancellation.
            await Task { for await _ in exit.exited {} }.value
        } onCancel: {
            self.terminateEscalating()
        }
        try Task.checkCancellation()
    }

    /// Sends SIGTERM now and SIGKILL if the child still runs after `processTerminationGrace`.
    /// Returns at once; `waitForExit(_:)` observes the exit.
    public func terminateEscalating() {
        guard isRunning else { return }
        terminate()
        Task {
            try? await Task.sleep(for: processTerminationGrace)
            if self.isRunning {
                kill(self.processIdentifier, SIGKILL)
            }
        }
    }
}
