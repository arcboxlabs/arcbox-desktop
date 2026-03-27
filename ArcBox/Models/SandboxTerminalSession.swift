import ArcBoxClient
import Foundation
import GRPCCore
import SwiftTerm

/// Manages an interactive sandbox exec session via gRPC bidirectional streaming.
///
/// Connects a SwiftTerm `TerminalView` to the sandbox's Exec RPC,
/// providing full bidirectional terminal I/O.
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

    var state: State = .idle

    @ObservationIgnored private weak var terminalView: TerminalView?
    @ObservationIgnored private var execTask: Task<Void, Never>?
    @ObservationIgnored private var inputContinuation: AsyncStream<Sandbox_V1_ExecInput>.Continuation?
    @ObservationIgnored private var sessionGeneration: Int = 0

    /// Connect to a sandbox shell via gRPC Exec.
    func connect(
        sandboxID: String,
        command: [String] = ["/bin/sh"],
        machineID: String,
        client: ArcBoxClient,
        terminalView: TerminalView
    ) {
        disconnect()

        sessionGeneration += 1
        let generation = sessionGeneration
        self.terminalView = terminalView
        state = .connecting

        let (inputStream, continuation) = AsyncStream<Sandbox_V1_ExecInput>.makeStream()
        self.inputContinuation = continuation

        // Get initial terminal size
        let terminalSize = terminalView.getTerminal().getDims()
        let cols = UInt32(terminalSize.cols)
        let rows = UInt32(terminalSize.rows)

        let metadata = SandboxMetadata.forMachine(machineID)

        execTask = Task { [weak self] in
            do {
                try await client.sandboxes.exec(
                    metadata: metadata,
                    requestProducer: { writer in
                        // Send init message
                        var initMsg = Sandbox_V1_ExecInput()
                        var execReq = Sandbox_V1_ExecRequest()
                        execReq.id = sandboxID
                        execReq.cmd = command
                        execReq.tty = true
                        execReq.ttySize.width = cols
                        execReq.ttySize.height = rows
                        initMsg.init_p = execReq
                        try await writer.write(initMsg)

                        // Stream stdin and resize events
                        for await input in inputStream {
                            try await writer.write(input)
                        }
                    },
                    onResponse: { response in
                        await MainActor.run {
                            guard let self, self.sessionGeneration == generation else { return }
                            self.state = .connected
                        }

                        for try await output in response.messages {
                            guard !Task.isCancelled else { break }
                            let data = output.data
                            let isDone = output.done

                            await MainActor.run {
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
                await MainActor.run {
                    guard let self, self.sessionGeneration == generation else { return }
                    self.state = .error(error.localizedDescription)
                }
            }

            await MainActor.run {
                guard let self, self.sessionGeneration == generation else { return }
                if self.state == .connected {
                    self.state = .disconnected
                }
            }
        }
    }

    /// Send terminal input data to the sandbox.
    func send(_ data: Data) {
        var msg = Sandbox_V1_ExecInput()
        msg.stdin = data
        inputContinuation?.yield(msg)
    }

    /// Notify the sandbox of terminal size changes.
    func resize(cols: Int, rows: Int) {
        var msg = Sandbox_V1_ExecInput()
        var size = Sandbox_V1_TerminalSize()
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
