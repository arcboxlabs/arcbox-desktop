import ArcBoxClient
import Foundation
import os
import SwiftTerm

/// Manages an interactive docker exec session using PTY + Process.
///
/// Connects a SwiftTerm `TerminalView` to a `docker exec -it` process,
/// providing full bidirectional terminal I/O with PTY support.
@MainActor
@Observable
class DockerTerminalSession {
    private enum Defaults {
        static let cols = 80
        static let rows = 24
        static let bufferSize = 8192
    }

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case error(String)
    }

    var state: State = .idle

    @ObservationIgnored private var process: Process?
    /// ABXD-17: File descriptor protected by a lock to prevent close races.
    /// `teardownProcess()` atomically swaps the FD to -1 under the lock,
    /// then closes the old FD outside the lock.  Readers (`send`, `resize`)
    /// take the lock to read a snapshot, guaranteeing they never operate on
    /// a closed or reused FD.
    @ObservationIgnored private let masterFDLock = OSAllocatedUnfairLock<Int32>(initialState: -1)
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private weak var terminalView: TerminalView?
    /// Monotonically increasing counter to distinguish sessions.
    /// Stale readTask / terminationHandler callbacks check this before modifying state.
    @ObservationIgnored private var sessionGeneration: Int = 0

    /// Store a terminal view reference for later use (called from makeNSView).
    func setTerminalView(_ tv: TerminalView) {
        self.terminalView = tv
    }

    /// Connect to a container's shell via `docker exec -it`.
    func connect(containerID: String, shell: String, terminalView: TerminalView) {
        launchDockerSession(
            arguments: ["exec", "-it", containerID, shell],
            terminalView: terminalView
        )
    }

    /// Run a temporary interactive container from an image via `docker run -it --rm`.
    func runImage(imageName: String, shell: String, terminalView: TerminalView) {
        launchDockerSession(
            arguments: ["run", "-it", "--rm", "--stop-timeout", "1", imageName, shell],
            terminalView: terminalView
        )
    }

    /// Connect to an image using the previously stored TerminalView.
    func connectImage(imageName: String, shell: String) {
        guard let tv = terminalView else { return }
        tv.feed(text: "\u{1b}[2J\u{1b}[H")
        launchDockerSession(
            arguments: ["run", "-it", "--rm", "--stop-timeout", "1", imageName, shell],
            terminalView: tv
        )
    }

    /// Shared implementation: launch a docker CLI process with PTY.
    private func launchDockerSession(arguments: [String], terminalView: TerminalView) {
        // Tear down old process without touching state (avoids intermediate .disconnected flicker)
        teardownProcess()
        self.terminalView = terminalView

        // Bump generation so stale callbacks from the old session are ignored
        sessionGeneration += 1
        let currentGen = sessionGeneration

        state = .connecting

        guard let dockerPath = Self.findDockerCLI() else {
            state = .error("Docker CLI not found")
            return
        }

        // Create PTY pair
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            state = .error("Failed to create PTY")
            return
        }
        masterFDLock.withLock { $0 = master }

        // Set initial terminal size from SwiftTerm (use sensible defaults if not yet laid out)
        let terminal = terminalView.getTerminal()
        let cols = max(terminal.cols, Defaults.cols)
        let rows = max(terminal.rows, Defaults.rows)
        var winSize = winsize()
        winSize.ws_col = UInt16(cols)
        winSize.ws_row = UInt16(rows)
        _ = ioctl(master, TIOCSWINSZ, &winSize)

        // Configure process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: dockerPath)
        proc.arguments = arguments
        // Ensure docker CLI connects to the ArcBox daemon socket
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["DOCKER_HOST"] = "unix://\(home)/.arcbox/run/docker.sock"
        proc.environment = env
        proc.standardInput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardOutput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardError = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        // Capture the master FD value for use in detached task
        let masterForRead = master

        // Start reading from PTY master
        readTask = Task.detached { [weak self] in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Defaults.bufferSize)
            defer { buffer.deallocate() }

            while !Task.isCancelled {
                let bytesRead = read(masterForRead, buffer, Defaults.bufferSize)
                if bytesRead <= 0 { break }
                let data = Array(UnsafeBufferPointer(start: buffer, count: bytesRead))
                await MainActor.run { [weak self] in
                    self?.terminalView?.feed(byteArray: ArraySlice(data))
                }
            }

            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == currentGen else { return }
                if self.state == .connected {
                    self.state = .disconnected
                }
            }
        }

        // Handle process termination — only modify state if this session is still current
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == currentGen else { return }
                if self.state == .connected {
                    self.state = .disconnected
                }
            }
        }

        do {
            try proc.run()
            // Close slave FD in parent process — the child owns it now
            close(slave)
            process = proc
            state = .connected
        } catch {
            close(slave)
            close(master)
            masterFDLock.withLock { $0 = -1 }
            state = .error(error.localizedDescription)
        }
    }

    /// Send data from the terminal to the docker exec process stdin.
    func send(_ data: Data) {
        let fd = masterFDLock.withLock { $0 }
        guard fd >= 0 else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            _ = write(fd, ptr, rawBuffer.count)
        }
    }

    /// Update the PTY window size (called when terminal view resizes).
    func resize(cols: Int, rows: Int) {
        let fd = masterFDLock.withLock { $0 }
        guard fd >= 0, cols > 0, rows > 0 else { return }
        var winSize = winsize()
        winSize.ws_col = UInt16(cols)
        winSize.ws_row = UInt16(rows)
        _ = ioctl(fd, TIOCSWINSZ, &winSize)
    }

    /// Disconnect and clean up the session.
    func disconnect() {
        teardownProcess()
        terminalView = nil
        if state == .connected || state == .connecting {
            state = .disconnected
        }
    }

    /// Tear down the current process and PTY without changing state or terminalView.
    /// Used by `launchDockerSession` to avoid intermediate `.disconnected` state flicker.
    private func teardownProcess() {
        readTask?.cancel()
        readTask = nil

        // Capture references before nilling them out
        let dyingProcess = process
        process = nil

        // ABXD-17: Atomically swap the FD to -1 under the lock so that
        // concurrent `send()` / `resize()` calls see -1 immediately and
        // never operate on the FD after it has been closed.
        let oldMasterFD = masterFDLock.withLock { fd -> Int32 in
            let prev = fd
            fd = -1
            return prev
        }

        // Move kill + close + dealloc entirely off the main thread.
        // Foundation's Process deallocation uses Mach ports that can
        // trigger "Unable to obtain a task name port right" errors
        // and potentially block the main thread.
        if dyingProcess != nil || oldMasterFD >= 0 {
            DispatchQueue.global(qos: .utility).async {
                if let proc = dyingProcess {
                    kill(proc.processIdentifier, SIGKILL)
                }
                if oldMasterFD >= 0 {
                    close(oldMasterFD)
                }
                // dyingProcess is released here when the closure exits,
                // allowing Foundation to deallocate on this background thread.
            }
        }
    }

    // MARK: - Docker CLI Discovery

    nonisolated private static let dockerSearchPaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/usr/bin/docker",
    ]

    nonisolated private static func findDockerCLI() -> String? {
        for path in dockerSearchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Fallback: check PATH
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["docker"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }
}
