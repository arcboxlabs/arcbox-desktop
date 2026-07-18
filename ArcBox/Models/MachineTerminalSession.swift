import ArcBoxClient
import Foundation
import GRPCCore
import SwiftTerm

/// Manages an interactive machine shell via the gRPC ExecSession
/// bidirectional stream.
///
/// Connects a SwiftTerm `TerminalView` to the machine's guest agent PTY,
/// providing full bidirectional terminal I/O with TTY resize support.
@MainActor
@Observable
class MachineTerminalSession {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case error(String)
    }

    var state: State = .idle

    @ObservationIgnored private weak var terminalView: TerminalView?
    @ObservationIgnored private var execTask: Task<Void, Never>?
    @ObservationIgnored private var inputContinuation:
        AsyncStream<Arcbox_V1_MachineExecInput>.Continuation?
    @ObservationIgnored private var sessionGeneration: Int = 0

    /// Connect to a machine shell via gRPC ExecSession.
    func connect(
        machineID: String,
        command: [String],
        client: ArcBoxClient,
        terminalView: TerminalView
    ) {
        disconnect()

        sessionGeneration += 1
        let generation = sessionGeneration
        self.terminalView = terminalView
        state = .connecting

        let (inputStream, continuation) = AsyncStream<Arcbox_V1_MachineExecInput>.makeStream()
        self.inputContinuation = continuation

        // Initial terminal size (sensible defaults if not yet laid out).
        let terminalSize = terminalView.getTerminal().getDims()
        let cols = UInt32(max(terminalSize.cols, 80))
        let rows = UInt32(max(terminalSize.rows, 24))

        execTask = Task.detached {
            do {
                try await client.machines.execSession(
                    requestProducer: { writer in
                        var initMsg = Arcbox_V1_MachineExecInput()
                        var execReq = Arcbox_V1_MachineExecRequest()
                        execReq.id = machineID
                        execReq.cmd = command
                        execReq.tty = true
                        execReq.ttySize.width = cols
                        execReq.ttySize.height = rows
                        initMsg.init_p = execReq
                        try await writer.write(initMsg)

                        // Stream stdin and resize events until disconnect.
                        for await input in inputStream {
                            try await writer.write(input)
                        }
                    },
                    onResponse: { response in
                        await MainActor.run { [weak self] in
                            guard let self, self.sessionGeneration == generation else { return }
                            self.state = .connected
                        }

                        for try await output in response.messages {
                            guard !Task.isCancelled else { break }
                            let data = output.data
                            let isDone = output.done

                            await MainActor.run { [weak self] in
                                guard let self, self.sessionGeneration == generation else { return }
                                if !data.isEmpty {
                                    let bytes = [UInt8](data)
                                    self.terminalView?.feed(byteArray: bytes[...])
                                }
                                if isDone {
                                    self.state = .disconnected
                                }
                            }
                        }
                    }
                )
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.sessionGeneration == generation else { return }
                    self.state = .error(ArcBoxClient.userMessage(for: error))
                }
            }

            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                if self.state == .connected {
                    self.state = .disconnected
                }
            }
        }
    }

    /// Send terminal input data to the machine.
    func send(_ data: Data) {
        var msg = Arcbox_V1_MachineExecInput()
        msg.stdin = data
        inputContinuation?.yield(msg)
    }

    /// Notify the machine of terminal size changes.
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        var msg = Arcbox_V1_MachineExecInput()
        var size = Arcbox_V1_TerminalSize()
        size.width = UInt32(cols)
        size.height = UInt32(rows)
        msg.resize = size
        inputContinuation?.yield(msg)
    }

    /// Disconnect the current session.
    func disconnect() {
        inputContinuation?.finish()
        inputContinuation = nil
        execTask?.cancel()
        execTask = nil
        if state == .connected || state == .connecting {
            state = .disconnected
        }
    }
}

/// Drives the shared SwiftTerm bridge.
extension MachineTerminalSession: TerminalIOSession {}
