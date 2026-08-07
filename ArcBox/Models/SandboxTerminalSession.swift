import ArcBoxClient
import Foundation
import GRPCCore
import SwiftTerm

/// Manages an interactive shell backed by an addressable sandbox execution.
///
/// Output attaches are resumable by absolute channel offset, while stdin uses
/// offset-idempotent unary writes so transport recovery cannot duplicate input.
@MainActor
@Observable
class SandboxTerminalSession {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case error(String)
    }

    private enum ControlEvent: Sendable {
        case input(Data)
        case resize(cols: UInt32, rows: UInt32)
    }

    private struct AttachResult: Sendable {
        var stdoutOffset: UInt64
        var stderrOffset: UInt64
        var exited: Bool
        var receivedEvent: Bool
        var error: (any Error)?
    }

    private struct ExecutionContext: Sendable {
        let sandboxID: String
        let executionID: String
        let machineID: String
        let client: ArcBoxClient
    }

    private struct TerminalSize: Sendable {
        let cols: UInt32
        let rows: UInt32
    }

    private enum TerminalProtocolError: Error, LocalizedError, Sendable {
        case attachEndedEarly
        case cleanupTimedOut
        case executionFailed(String)
        case stdinOffsetRegressed
        case stdinDidNotAdvance

        var errorDescription: String? {
            switch self {
            case .attachEndedEarly:
                "The terminal output stream ended before the execution exited."
            case .cleanupTimedOut:
                "The previous terminal is still closing. Try again after ArcBox reconnects."
            case .executionFailed(let message):
                message
            case .stdinOffsetRegressed:
                "The sandbox reported an invalid stdin offset."
            case .stdinDidNotAdvance:
                "The sandbox did not accept terminal input."
            }
        }
    }

    private enum TerminationProgress {
        case active
        case finished
        case retry
    }

    var state: State = .idle

    @ObservationIgnored private weak var terminalView: TerminalView?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupToken: UUID?
    @ObservationIgnored private var controlContinuation: AsyncStream<ControlEvent>.Continuation?
    @ObservationIgnored private var sessionGeneration = 0
    @ObservationIgnored private var startingGeneration: Int?
    @ObservationIgnored private var activeContext: ExecutionContext?

    func connect(
        sandboxID: String,
        command: [String] = ["/bin/sh"],
        machineID: String,
        client: ArcBoxClient,
        terminalView: TerminalView
    ) {
        disconnect()

        let hasPendingCleanup = cleanupToken != nil
        let generation = sessionGeneration
        let context = ExecutionContext(
            sandboxID: sandboxID,
            executionID: UUID().uuidString.lowercased(),
            machineID: machineID,
            client: client
        )
        self.terminalView = terminalView
        state = .connecting

        let (controlStream, continuation) = AsyncStream<ControlEvent>.makeStream()
        controlContinuation = continuation

        let terminalSize = terminalView.getTerminal().getDims()
        let size = TerminalSize(
            cols: UInt32(max(terminalSize.cols, 80)),
            rows: UInt32(max(terminalSize.rows, 24))
        )

        sessionTask = Task {
            if hasPendingCleanup {
                guard await self.waitForCleanup(generation: generation) else {
                    guard generation == self.sessionGeneration else { return }
                    self.controlContinuation?.finish()
                    self.controlContinuation = nil
                    self.sessionTask = nil
                    self.state = .error(TerminalProtocolError.cleanupTimedOut.localizedDescription)
                    return
                }
            }
            guard generation == self.sessionGeneration else { return }
            self.startingGeneration = generation
            await self.runSession(
                context: context,
                command: command,
                size: size,
                controlStream: controlStream,
                generation: generation
            )
        }
    }

    func send(_ data: Data) {
        guard !data.isEmpty else { return }
        controlContinuation?.yield(.input(data))
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        controlContinuation?.yield(.resize(cols: UInt32(cols), rows: UInt32(rows)))
    }

    /// Stop the owned execution before cancelling its local streams.
    func disconnect() {
        let hasPendingStart = startingGeneration != nil
        startingGeneration = nil
        sessionGeneration += 1

        let task = sessionTask
        let continuation = controlContinuation
        let context = activeContext

        sessionTask = nil
        controlContinuation = nil
        activeContext = nil
        continuation?.finish()

        if let context {
            beginCleanup {
                await self.terminateExecution(context)
                task?.cancel()
                if let task {
                    await task.value
                }
            }
        } else if let task, hasPendingStart {
            // A pending StartExecution is left alive long enough to resolve its
            // idempotent execution ID; runSession then terminates it itself.
            beginCleanup {
                await task.value
            }
        } else {
            task?.cancel()
        }

        if state == .connected || state == .connecting {
            state = .disconnected
        }
    }

    private func runSession(
        context: ExecutionContext,
        command: [String],
        size: TerminalSize,
        controlStream: AsyncStream<ControlEvent>,
        generation: Int
    ) async {
        do {
            let execution = try await startExecution(
                context: context,
                command: command,
                size: size
            )
            if startingGeneration == generation {
                startingGeneration = nil
            }

            guard generation == sessionGeneration else {
                await terminateExecution(context)
                return
            }

            activeContext = context

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.attachUntilExit(
                        context: context,
                        generation: generation
                    )
                }
                group.addTask {
                    try await self.runControlPump(
                        controlStream,
                        initialStdinOffset: execution.stdin.bytesWritten,
                        stdinClosed: execution.stdin.closed,
                        context: context,
                        generation: generation
                    )
                }
                _ = try await group.next()
                group.cancelAll()
            }

            guard generation == sessionGeneration else { return }
            finishCurrentSession()
        } catch {
            if startingGeneration == generation {
                startingGeneration = nil
            }
            guard !Task.isCancelled else { return }
            guard generation == sessionGeneration else {
                await terminateExecution(context)
                return
            }
            controlContinuation?.finish()
            controlContinuation = nil
            activeContext = nil
            sessionTask = nil
            state = .error(ArcBoxClient.userMessage(for: error))
            beginCleanup {
                await self.terminateExecution(context)
            }
        }
    }

    private func startExecution(
        context: ExecutionContext,
        command: [String],
        size: TerminalSize
    ) async throws -> Arcbox_Sandbox_V1_Execution {
        var request = Arcbox_Sandbox_V1_StartExecutionRequest()
        request.sandboxID = context.sandboxID
        request.executionID = context.executionID
        request.cmd = command
        request.tty = true
        request.stdin = true
        request.ttySize.width = size.cols
        request.ttySize.height = size.rows
        let metadata = SandboxMetadata.forMachine(context.machineID)

        for attempt in 0..<3 {
            do {
                return try await context.client.sandboxProcesses.startExecution(
                    request,
                    metadata: metadata,
                    options: ArcBoxClient.defaultCallOptions
                )
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                guard attempt < 2, Self.isRetryableTransportError(error) else { throw error }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        preconditionFailure("StartExecution retry loop must return or throw")
    }

    private func attachUntilExit(
        context: ExecutionContext,
        generation: Int
    ) async throws {
        var stdoutOffset: UInt64 = 0
        var stderrOffset: UInt64 = 0
        var resumeFailures = 0
        let metadata = SandboxMetadata.forMachine(context.machineID)

        while !Task.isCancelled {
            var request = Arcbox_Sandbox_V1_AttachExecutionRequest()
            request.sandboxID = context.sandboxID
            request.executionID = context.executionID
            request.stdoutOffset = stdoutOffset
            request.stderrOffset = stderrOffset
            let requestedStdoutOffset = stdoutOffset
            let requestedStderrOffset = stderrOffset

            do {
                let result: AttachResult = try await context.client.sandboxProcesses.attachExecution(
                    request,
                    metadata: metadata
                ) { response in
                    var stdoutOffset = requestedStdoutOffset
                    var stderrOffset = requestedStderrOffset
                    var receivedEvent = false

                    do {
                        for try await event in response.messages {
                            try Task.checkCancellation()
                            receivedEvent = true

                            switch event.event {
                            case .started:
                                await self.markConnected(generation: generation)

                            case .output(let output):
                                (stdoutOffset, stderrOffset) = await self.consume(
                                    output,
                                    stdoutOffset: stdoutOffset,
                                    stderrOffset: stderrOffset,
                                    generation: generation
                                )

                            case .exited(let exited):
                                if !exited.execution.error.isEmpty {
                                    throw TerminalProtocolError.executionFailed(
                                        exited.execution.error
                                    )
                                }
                                await self.markExited(generation: generation)
                                return AttachResult(
                                    stdoutOffset: stdoutOffset,
                                    stderrOffset: stderrOffset,
                                    exited: true,
                                    receivedEvent: receivedEvent,
                                    error: nil
                                )

                            case .keepAlive, nil:
                                continue
                            }
                        }
                    } catch {
                        return AttachResult(
                            stdoutOffset: stdoutOffset,
                            stderrOffset: stderrOffset,
                            exited: false,
                            receivedEvent: receivedEvent,
                            error: error
                        )
                    }

                    return AttachResult(
                        stdoutOffset: stdoutOffset,
                        stderrOffset: stderrOffset,
                        exited: false,
                        receivedEvent: receivedEvent,
                        error: nil
                    )
                }

                stdoutOffset = result.stdoutOffset
                stderrOffset = result.stderrOffset
                if result.exited {
                    return
                }
                if result.receivedEvent {
                    resumeFailures = 0
                }
                if let error = result.error {
                    throw error
                }
                break
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                guard Self.isRetryableTransportError(error) else { throw error }
                resumeFailures += 1
                guard resumeFailures <= 3 else { break }
            }

            try await Task.sleep(for: .milliseconds(Int64(resumeFailures * 500)))
        }

        try await waitForExecution(context: context, generation: generation)
    }

    private func runControlPump(
        _ events: AsyncStream<ControlEvent>,
        initialStdinOffset: UInt64,
        stdinClosed: Bool,
        context: ExecutionContext,
        generation: Int
    ) async throws {
        var stdinOffset = initialStdinOffset
        var stdinClosed = stdinClosed

        for await event in events {
            try Task.checkCancellation()
            guard generation == sessionGeneration else { continue }

            switch event {
            case .input(let data) where !stdinClosed:
                (stdinOffset, stdinClosed) = try await writeInput(
                    data,
                    from: stdinOffset,
                    context: context
                )

            case .resize(let cols, let rows):
                try await resizeExecution(
                    cols: cols,
                    rows: rows,
                    context: context
                )

            case .input:
                break
            }
        }
    }

    private func writeInput(
        _ data: Data,
        from initialOffset: UInt64,
        context: ExecutionContext
    ) async throws -> (offset: UInt64, closed: Bool) {
        var offset = initialOffset
        var consumed = 0
        var failures = 0
        let metadata = SandboxMetadata.forMachine(context.machineID)

        while consumed < data.count {
            let remaining = Data(data.dropFirst(consumed))
            var request = Arcbox_Sandbox_V1_WriteStdinRequest()
            request.sandboxID = context.sandboxID
            request.executionID = context.executionID
            request.offset = offset
            request.data = remaining

            do {
                let status = try await context.client.sandboxProcesses.writeStdin(
                    request,
                    metadata: metadata,
                    options: ArcBoxClient.defaultCallOptions
                )
                guard status.bytesWritten >= offset else {
                    throw TerminalProtocolError.stdinOffsetRegressed
                }

                let accepted = min(
                    status.bytesWritten - offset,
                    UInt64(remaining.count)
                )
                guard accepted > 0 || status.closed else {
                    throw TerminalProtocolError.stdinDidNotAdvance
                }

                consumed += Int(accepted)
                offset = status.bytesWritten
                failures = 0
                if status.closed {
                    return (offset, true)
                }
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                let writeError = error
                failures += 1
                guard failures <= 3 else { throw writeError }

                do {
                    var statusRequest = Arcbox_Sandbox_V1_GetStdinStatusRequest()
                    statusRequest.sandboxID = context.sandboxID
                    statusRequest.executionID = context.executionID
                    let status = try await context.client.sandboxProcesses.getStdinStatus(
                        statusRequest,
                        metadata: metadata,
                        options: ArcBoxClient.defaultCallOptions
                    )
                    guard status.bytesWritten >= offset else {
                        throw TerminalProtocolError.stdinOffsetRegressed
                    }

                    let accepted = min(
                        status.bytesWritten - offset,
                        UInt64(remaining.count)
                    )
                    consumed += Int(accepted)
                    offset = status.bytesWritten
                    if accepted > 0 {
                        failures = 0
                    } else if failures == 3 {
                        throw writeError
                    }
                    if status.closed {
                        return (offset, true)
                    }
                } catch {
                    guard failures < 3 else { throw error }
                }

                if consumed < data.count {
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
        }

        return (offset, false)
    }

    private func resizeExecution(
        cols: UInt32,
        rows: UInt32,
        context: ExecutionContext
    ) async throws {
        var request = Arcbox_Sandbox_V1_ResizeExecutionTtyRequest()
        request.sandboxID = context.sandboxID
        request.executionID = context.executionID
        request.size.width = cols
        request.size.height = rows
        let metadata = SandboxMetadata.forMachine(context.machineID)

        for attempt in 0..<3 {
            do {
                _ = try await context.client.sandboxProcesses.resizeExecutionTty(
                    request,
                    metadata: metadata,
                    options: ArcBoxClient.defaultCallOptions
                )
                return
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                guard attempt < 2, Self.isRetryableTransportError(error) else { throw error }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func terminateExecution(_ context: ExecutionContext) async {
        var retryDelay: Int64 = 250

        while !Task.isCancelled {
            switch await sendSignal(.sighup, context: context) {
            case .finished:
                return
            case .active:
                if await waitForExit(context) == .finished {
                    return
                }
                switch await sendSignal(.sigkill, context: context) {
                case .finished:
                    return
                case .active:
                    if await waitForExit(context) == .finished {
                        return
                    }
                case .retry:
                    break
                }
            case .retry:
                break
            }

            do {
                try await Task.sleep(for: .milliseconds(retryDelay))
            } catch {
                return
            }
            retryDelay = min(retryDelay * 2, 2_000)
        }
    }

    private func sendSignal(
        _ signal: Arcbox_Sandbox_V1_Signal,
        context: ExecutionContext
    ) async -> TerminationProgress {
        var options = ArcBoxClient.defaultCallOptions
        options.timeout = .seconds(2)
        let metadata = SandboxMetadata.forMachine(context.machineID)
        var request = Arcbox_Sandbox_V1_SignalExecutionRequest()
        request.sandboxID = context.sandboxID
        request.executionID = context.executionID
        request.signal = signal
        do {
            _ = try await context.client.sandboxProcesses.signalExecution(
                request,
                metadata: metadata,
                options: options
            )
            return .active
        } catch {
            return Self.terminationProgress(for: error)
        }
    }

    private func waitForExit(_ context: ExecutionContext) async -> TerminationProgress {
        var options = ArcBoxClient.defaultCallOptions
        options.timeout = .seconds(3)
        let metadata = SandboxMetadata.forMachine(context.machineID)
        var request = Arcbox_Sandbox_V1_WaitExecutionRequest()
        request.sandboxID = context.sandboxID
        request.executionID = context.executionID
        request.timeoutSeconds = 2
        do {
            let execution = try await context.client.sandboxProcesses.waitExecution(
                request,
                metadata: metadata,
                options: options
            )
            return execution.state == .exited ? .finished : .active
        } catch {
            return Self.terminationProgress(for: error)
        }
    }

    private static func terminationProgress(for error: Error) -> TerminationProgress {
        guard let rpcError = error as? RPCError else { return .retry }
        switch rpcError.code {
        case .notFound, .failedPrecondition:
            return .finished
        default:
            return .retry
        }
    }

    private func markConnected(generation: Int) {
        guard generation == sessionGeneration else { return }
        state = .connected
        Analytics.capture(.terminalOpened, properties: ["surface": "sandbox"])
    }

    private func feed(_ data: Data.SubSequence, generation: Int) {
        guard generation == sessionGeneration, !data.isEmpty else { return }
        let bytes = [UInt8](data)
        terminalView?.feed(byteArray: bytes[...])
    }

    private func markExited(generation: Int) {
        guard generation == sessionGeneration else { return }
        state = .disconnected
    }

    private func finishCurrentSession() {
        controlContinuation?.finish()
        controlContinuation = nil
        activeContext = nil
        sessionTask = nil
        if state == .connected || state == .connecting {
            state = .disconnected
        }
    }

    private static func isRetryableTransportError(_ error: Error) -> Bool {
        guard !(error is CancellationError) else { return false }
        guard !(error is TerminalProtocolError) else { return false }
        guard let rpcError = error as? RPCError else { return true }
        switch rpcError.code {
        case .cancelled, .deadlineExceeded, .unavailable:
            return true
        default:
            return false
        }
    }
}

extension SandboxTerminalSession {
    fileprivate func consume(
        _ output: Arcbox_Sandbox_V1_ExecutionOutput,
        stdoutOffset: UInt64,
        stderrOffset: UInt64,
        generation: Int
    ) async -> (stdoutOffset: UInt64, stderrOffset: UInt64) {
        let currentOffset: UInt64
        switch output.channel {
        case .stdout, .pty:
            currentOffset = stdoutOffset
        case .stderr:
            currentOffset = stderrOffset
        case .unspecified, .UNRECOGNIZED:
            return (stdoutOffset, stderrOffset)
        }

        let nextOffset = output.offset + UInt64(output.data.count)
        guard nextOffset > currentOffset else {
            return (stdoutOffset, stderrOffset)
        }

        let skipped = Int(max(currentOffset, output.offset) - output.offset)
        feed(output.data.dropFirst(skipped), generation: generation)

        switch output.channel {
        case .stdout, .pty:
            return (nextOffset, stderrOffset)
        case .stderr:
            return (stdoutOffset, nextOffset)
        case .unspecified, .UNRECOGNIZED:
            return (stdoutOffset, stderrOffset)
        }
    }

    private func waitForExecution(
        context: ExecutionContext,
        generation: Int
    ) async throws {
        var request = Arcbox_Sandbox_V1_WaitExecutionRequest()
        request.sandboxID = context.sandboxID
        request.executionID = context.executionID
        request.timeoutSeconds = 3_600
        let metadata = SandboxMetadata.forMachine(context.machineID)
        var options = ArcBoxClient.defaultCallOptions
        options.timeout = .seconds(3_605)

        let execution = try await context.client.sandboxProcesses.waitExecution(
            request,
            metadata: metadata,
            options: options
        )
        guard execution.state == .exited else {
            throw TerminalProtocolError.attachEndedEarly
        }
        if !execution.error.isEmpty {
            throw TerminalProtocolError.executionFailed(execution.error)
        }
        markExited(generation: generation)
    }

    fileprivate func waitForCleanup(generation: Int) async -> Bool {
        for _ in 0..<60 {
            guard generation == sessionGeneration else { return false }
            guard cleanupToken != nil else { return true }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return false
            }
        }
        return cleanupToken == nil
    }

    fileprivate func beginCleanup(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        let token = UUID()
        cleanupToken = token
        cleanupTask = Task {
            await operation()
            guard cleanupToken == token else { return }
            cleanupToken = nil
            cleanupTask = nil
        }
    }
}

extension SandboxTerminalSession: TerminalIOSession {}
