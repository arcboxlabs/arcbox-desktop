import ArcBoxClient
import Foundation
import SwiftTerm
import os

/// Manages an interactive docker exec session using PTY + Process.
///
/// Connects a SwiftTerm `TerminalView` to a `docker exec -it` process,
/// providing full bidirectional terminal I/O with PTY support.
@MainActor
@Observable
class DockerTerminalSession {
    nonisolated private enum Defaults {
        static let cols = 80
        static let rows = 24
        static let bufferSize = 8192
    }

    nonisolated private struct DockerCommandResult {
        let status: Int32
        let error: String
    }

    nonisolated private struct ImageContainer: Sendable {
        let name: String
        let dockerPath: String
        let environment: [String: String]

        func run(_ arguments: [String]) throws -> DockerCommandResult {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: dockerPath)
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            let errorOutput = Pipe()
            process.standardError = errorOutput
            try process.run()
            process.waitUntilExit()
            let data = errorOutput.fileHandleForReading.readDataToEndOfFile()
            return DockerCommandResult(
                status: process.terminationStatus,
                error: String(data: data, encoding: .utf8) ?? "unreadable Docker error"
            )
        }
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
    @ObservationIgnored private let ptyFDLock = OSAllocatedUnfairLock<Int32>(initialState: -1)
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private weak var terminalView: TerminalView?
    @ObservationIgnored private var imageContainer: ImageContainer?
    /// Monotonically increasing counter to distinguish sessions.
    /// Stale readTask / terminationHandler callbacks check this before modifying state.
    @ObservationIgnored private var sessionGeneration: Int = 0

    var activeImageContainerName: String? { imageContainer?.name }

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
        launchImageSession(imageName: imageName, shell: shell, terminalView: terminalView)
    }

    /// Connect to an image using the previously stored TerminalView.
    func connectImage(imageName: String, shell: String) {
        guard let tv = terminalView else { return }
        tv.feed(text: "\u{1b}[2J\u{1b}[H")
        launchImageSession(imageName: imageName, shell: shell, terminalView: tv)
    }

    private func launchImageSession(imageName: String, shell: String, terminalView: TerminalView) {
        let containerName = "arcbox-image-terminal-\(UUID().uuidString.lowercased())"
        launchDockerSession(
            arguments: [
                "run", "-it", "--rm", "--stop-timeout", "1", "--name", containerName,
                imageName, shell,
            ],
            terminalView: terminalView,
            imageContainerName: containerName
        )
    }

    /// Shared implementation: launch a docker CLI process with PTY.
    private func launchDockerSession(
        arguments: [String],
        terminalView: TerminalView,
        imageContainerName: String? = nil
    ) {
        sessionGeneration += 1
        // Tear down old process without touching state (avoids intermediate .disconnected flicker)
        teardownProcess()
        self.terminalView = terminalView

        let currentGen = sessionGeneration

        state = .connecting

        guard let dockerPath = DockerCLIResolver.findDockerCLI() else {
            state = .error("Docker CLI not found")
            return
        }

        // Create PTY pair
        var primary: Int32 = -1
        var replica: Int32 = -1
        guard openpty(&primary, &replica, nil, nil, nil) == 0 else {
            state = .error("Failed to create PTY")
            return
        }
        let ptyFD = primary
        ptyFDLock.withLock { $0 = ptyFD }

        // Set initial terminal size from SwiftTerm (use sensible defaults if not yet laid out)
        let terminal = terminalView.getTerminal()
        let cols = max(terminal.cols, Defaults.cols)
        let rows = max(terminal.rows, Defaults.rows)
        var winSize = winsize()
        winSize.ws_col = UInt16(cols)
        winSize.ws_row = UInt16(rows)
        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: primary, windowSize: &winSize)

        // Configure process — use pstramp when available for proper
        // session isolation and controlling-terminal setup.
        let proc = Process()
        var env = Self.sanitizedEnvironment()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDir = profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        env["DOCKER_HOST"] = "unix://\(home)/\(dataDir)/run/docker.sock"
        env["TERM"] = "xterm-256color"
        proc.environment = env

        if let pstrampPath = Self.findPstramp() {
            // -setctty: new session + PTY replica becomes controlling terminal
            // -disclaim: relinquish macOS responsibility claims
            proc.executableURL = URL(fileURLWithPath: pstrampPath)
            proc.arguments = ["-setctty", "-disclaim", "--", dockerPath] + arguments
        } else {
            proc.executableURL = URL(fileURLWithPath: dockerPath)
            proc.arguments = arguments
        }
        proc.standardInput = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
        proc.standardOutput = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
        proc.standardError = FileHandle(fileDescriptor: replica, closeOnDealloc: false)

        // Capture the primary FD value for use in detached task
        let ptyForRead = primary

        // Start reading from PTY primary
        readTask = Task.detached { [weak self] in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Defaults.bufferSize)
            defer { buffer.deallocate() }

            while !Task.isCancelled {
                let bytesRead = read(ptyForRead, buffer, Defaults.bufferSize)
                if bytesRead <= 0 { break }
                let data = Array(UnsafeBufferPointer(start: buffer, count: bytesRead))
                await MainActor.run { [weak self] in
                    guard let self, self.sessionGeneration == currentGen else { return }
                    self.terminalView?.feed(byteArray: data[...])
                }
            }

            await MainActor.run { [weak self] in
                guard let self, self.sessionGeneration == currentGen else { return }
                if self.state == .connected {
                    self.teardownProcess()
                    self.state = .disconnected
                }
            }
        }

        // Handle process termination — only modify state if this session is still current
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == currentGen else { return }
                if self.state == .connected {
                    self.teardownProcess()
                    self.state = .disconnected
                }
            }
        }

        do {
            try proc.run()
            // Close replica FD in parent process — the child owns it now
            close(replica)
            process = proc
            if let imageContainerName {
                imageContainer = ImageContainer(
                    name: imageContainerName,
                    dockerPath: dockerPath,
                    environment: env
                )
            }
            state = .connected
            // `imageContainerName` is set only by the image paths, so it is
            // already the surface discriminator — no second parameter to drift.
            Analytics.capture(
                .terminalOpened,
                properties: ["surface": imageContainerName == nil ? "container" : "image"])
        } catch {
            close(replica)
            close(primary)
            ptyFDLock.withLock { $0 = -1 }
            state = .error(error.localizedDescription)
        }
    }

    /// Send data from the terminal to the docker exec process stdin.
    func send(_ data: Data) {
        let fd = ptyFDLock.withLock { $0 }
        guard fd >= 0 else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            _ = write(fd, ptr, rawBuffer.count)
        }
    }

    /// Update the PTY window size (called when terminal view resizes).
    func resize(cols: Int, rows: Int) {
        let fd = ptyFDLock.withLock { $0 }
        guard fd >= 0, cols > 0, rows > 0 else { return }
        var winSize = winsize()
        winSize.ws_col = UInt16(cols)
        winSize.ws_row = UInt16(rows)
        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: fd, windowSize: &winSize)
    }

    /// Disconnect and clean up the session.
    func disconnect() {
        sessionGeneration += 1
        teardownProcess()
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
        let dyingImageContainer = imageContainer
        process = nil
        imageContainer = nil

        // ABXD-17: Atomically swap the FD to -1 under the lock so that
        // concurrent `send()` / `resize()` calls see -1 immediately and
        // never operate on the FD after it has been closed.
        let oldPtyFD = ptyFDLock.withLock { fd -> Int32 in
            let prev = fd
            fd = -1
            return prev
        }

        // Move kill + close + dealloc entirely off the main thread.
        // Foundation's Process deallocation uses Mach ports that can
        // trigger "Unable to obtain a task name port right" errors
        // and potentially block the main thread.
        if dyingProcess != nil || dyingImageContainer != nil || oldPtyFD >= 0 {
            DispatchQueue.global(qos: .utility).async {
                if let container = dyingImageContainer {
                    do {
                        let result = try container.run(["stop", "--timeout", "1", container.name])
                        if result.status != 0, !result.error.contains("No such container") {
                            Log.terminal.error(
                                "Failed to stop image terminal container \(container.name, privacy: .private): \(result.error, privacy: .private)"
                            )
                        }
                    } catch {
                        Log.terminal.error(
                            "Failed to stop image terminal container \(container.name, privacy: .private): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }

                if oldPtyFD >= 0 {
                    close(oldPtyFD)
                }
                if let proc = dyingProcess {
                    if proc.isRunning {
                        kill(proc.processIdentifier, SIGKILL)
                    }
                    proc.waitUntilExit()
                }

                if let container = dyingImageContainer {
                    // `docker stop` does not AutoRemove a container that was created but never started.
                    // ponytail: retry for one second so an in-flight create request can publish after launcher exit.
                    for attempt in 0..<20 {
                        let result: DockerCommandResult
                        do {
                            result = try container.run([
                                "container", "rm", "--force", "--volumes", container.name,
                            ])
                        } catch {
                            let message = error.localizedDescription
                            Log.terminal.error(
                                "Failed to remove image terminal container \(container.name, privacy: .private): \(message, privacy: .public)"
                            )
                            break
                        }
                        guard result.status != 0 else { break }
                        let canRetry =
                            result.error.contains("No such container")
                            || result.error.contains("already in progress")
                        guard canRetry else {
                            Log.terminal.error(
                                "Failed to remove image terminal container \(container.name, privacy: .private): \(result.error, privacy: .private)"
                            )
                            break
                        }
                        guard attempt < 19 else { break }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
                // dyingProcess is released here when the closure exits,
                // allowing Foundation to deallocate on this background thread.
            }
        }
    }

    // MARK: - Environment & Trampoline

    /// GUI-specific keys stripped before spawning child processes.
    /// `__CFBundleIdentifier` causes macOS to attribute the child to the
    /// desktop app; the others leak irrelevant GUI metadata into the session.
    nonisolated private static let envKeysToStrip: Set<String> = [
        "__CFBundleIdentifier",
        "Apple_PubSub_Socket_Render",
        "SECURITYSESSIONID",
    ]

    nonisolated private static func sanitizedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in envKeysToStrip {
            env.removeValue(forKey: key)
        }
        return env
    }

    /// Locate pstramp in the app bundle (Contents/MacOS/pstramp).
    nonisolated private static func findPstramp() -> String? {
        guard let macosDir = Bundle.main.executableURL?.deletingLastPathComponent() else {
            return nil
        }
        let path = macosDir.appendingPathComponent("pstramp").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

}

/// Drives the shared SwiftTerm bridge.
extension DockerTerminalSession: TerminalIOSession {}
