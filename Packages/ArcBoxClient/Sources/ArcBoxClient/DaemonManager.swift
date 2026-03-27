import Foundation
import Observation
import OSLog
import ServiceManagement

/// Daemon connection state derived from SMAppService registration + gRPC stream.
public enum DaemonState: Sendable, Equatable {
    case stopped        // Not registered with launchd
    case starting       // Enable in progress
    case stopping       // Disable in progress
    case registered     // Registered but gRPC stream not connected yet
    case running        // gRPC stream connected, daemon alive
    case error(String)

    public var isRunning: Bool { self == .running }
}

/// Daemon setup phase, mirroring the proto `SetupStatus.Phase`.
public enum DaemonSetupPhase: Sendable, Equatable {
    case unknown
    case initializing
    case downloadingAssets
    case assetsReady
    case vmStarting
    case vmReady
    case networkReady
    case ready
    case degraded
}

/// Manages the arcbox daemon lifecycle via SMAppService (LaunchAgent) and
/// observes readiness via gRPC `WatchSetupStatus` stream.
///
/// The daemon binary is bundled in the app at `Contents/Helpers/com.arcboxlabs.desktop.daemon`
/// and managed by launchd. `KeepAlive` in the plist ensures automatic restart on crash.
@Observable
@MainActor
public final class DaemonManager {
    /// Current daemon state.
    public private(set) var state: DaemonState = .stopped

    /// Current setup phase reported by the daemon's gRPC stream.
    public private(set) var setupPhase: DaemonSetupPhase = .unknown

    /// Human-readable status message from the daemon.
    public private(set) var setupMessage: String = ""

    /// Whether the DNS resolver is installed (from daemon status).
    public private(set) var dnsResolverInstalled: Bool = false

    /// Whether the Docker socket is linked (from daemon status).
    public private(set) var dockerSocketLinked: Bool = false

    /// Whether the container subnet route is installed (from daemon status).
    public private(set) var routeInstalled: Bool = false

    /// Whether the default VM is running (from daemon status).
    public private(set) var vmRunning: Bool = false

    /// Whether Docker CLI tools are installed (from daemon status).
    public private(set) var dockerToolsInstalled: Bool = false

    /// Last error message from enable/disable operations.
    public private(set) var errorMessage: String?

    private nonisolated static let daemonPlistName = "com.arcboxlabs.desktop.daemon.plist"
    private nonisolated var daemonService: SMAppService {
        SMAppService.agent(plistName: Self.daemonPlistName)
    }

    /// Whether the privileged helper is installed.
    public private(set) var helperInstalled: Bool = false

    private var watchTask: Task<Void, Never>?

    public init() {}

    // MARK: - Helper Lifecycle

    /// Installs the privileged helper via `abctl _install` with a macOS
    /// admin password prompt.
    ///
    /// SMAppService.daemon() is unreliable — macOS registers the daemon
    /// as disabled without notifying the user, and System Settings provides
    /// no toggle to enable it. Instead, we use osascript to trigger the
    /// standard macOS "wants to make changes" password dialog, the same
    /// approach used by Docker Desktop and OrbStack.
    ///
    /// Skips silently if the installed helper version matches the bundled one.
    /// Only prompts for password on first install or upgrade.
    /// Installed helper binary path (must match arcbox-constants privileged::HELPER_BINARY).
    private nonisolated static let installedHelperPath = "/usr/local/libexec/arcbox-helper"

    public func installHelper() async {
        // Find abctl and helper in the app bundle.
        let bundle = Bundle.main.bundleURL
        let abctl = bundle.appendingPathComponent("Contents/MacOS/bin/abctl").path
        let helper = bundle.appendingPathComponent("Contents/MacOS/bin/arcbox-helper").path
        guard FileManager.default.isExecutableFile(atPath: abctl) else {
            ClientLog.daemon.warning("abctl not found in bundle, skipping helper install")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            ClientLog.daemon.warning("arcbox-helper not found in bundle, skipping helper install")
            return
        }

        // Skip if installed helper is the same version as the bundled one.
        let installedVersion = binaryVersion(Self.installedHelperPath)
        let bundledVersion = binaryVersion(helper)
        if let iv = installedVersion, let bv = bundledVersion, iv == bv {
            helperInstalled = true
            ClientLog.daemon.info("Helper \(iv, privacy: .public) already installed")
            return
        }

        ClientLog.daemon.info("Installing helper via abctl _install")

        func shellQuote(_ s: String) -> String {
            "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        let cmd = "\(shellQuote(abctl)) _install --no-daemon --no-shell --helper-path \(shellQuote(helper))"
        let script = "do shell script \"\(cmd)\" with administrator privileges"

        let result = await Task.detached { () -> Bool in
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error {
                    ClientLog.daemon.warning("Helper install failed: \(error, privacy: .public)")
                    return false
                }
                return true
            }
            return false
        }.value

        helperInstalled = result
        if result {
            ClientLog.daemon.info("Helper installed successfully")
        }
    }

    // MARK: - Daemon Lifecycle

    /// Register the daemon with launchd. Does not wait for reachability —
    /// that is handled by ``connectAndWatch(client:)``.
    public func enableDaemon() async {
        errorMessage = nil
        state = .starting

        // Ensure data directory exists so the daemon can create sockets and state.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try? FileManager.default.createDirectory(
            atPath: "\(home)/.arcbox/run", withIntermediateDirectories: true)

        let status = daemonService.status
        ClientLog.daemon.info("SMAppService status: \(String(describing: status), privacy: .public)")

        // If already enabled, skip the destructive unregister+register cycle.
        // This avoids killing a healthy daemon when enableDaemon() is called
        // redundantly (e.g. SwiftUI .task re-entrancy).
        if status == .enabled {
            ClientLog.daemon.info("Daemon already registered, skipping re-register")
            if state != .running {
                state = .registered
            }
            return
        }

        do {
            // Force re-register to ensure BundleProgram resolves against the current
            // app bundle path.
            try? await daemonService.unregister()
            try daemonService.register()
            ClientLog.daemon.info("Service registered successfully")
            state = .registered
        } catch {
            ClientLog.daemon.error("Failed to register: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            state = .error("Failed to register daemon: \(error.localizedDescription)")
        }
    }

    /// Unregister the daemon from launchd.
    public func disableDaemon() async {
        stopWatching()
        errorMessage = nil
        state = .stopping

        do {
            try await daemonService.unregister()
        } catch {
            errorMessage = error.localizedDescription
        }

        state = .stopped
    }

    // MARK: - gRPC Setup Status Stream

    /// Connect to the daemon's `WatchSetupStatus` gRPC stream and drive
    /// state updates from the stream. When the stream connects, the daemon
    /// is alive. When it disconnects, the daemon died.
    ///
    /// This replaces the old `/_ping` polling approach.
    @available(macOS 15.0, *)
    public func connectAndWatch(client: ArcBoxClient) {
        stopWatching()
        let systemService = client.system
        watchTask = Task { [weak self] in
            // Retry loop: reconnect on stream disconnect.
            while !Task.isCancelled {
                // Bridge: gRPC Sendable closure writes into the stream,
                // MainActor-isolated code reads from it.
                let (stream, continuation) = AsyncStream<Arcbox_V1_SetupStatus>.makeStream()

                let rpcTask = Task.detached {
                    do {
                        try await systemService.watchSetupStatus(
                            request: .init(message: .init())
                        ) { response in
                            for try await message in response.messages {
                                continuation.yield(message)
                            }
                        }
                    } catch {
                        ClientLog.daemon.warning("WatchSetupStatus stream error: \(error.localizedDescription, privacy: .public)")
                    }
                    continuation.finish()
                }

                for await message in stream {
                    guard !Task.isCancelled else { break }
                    self?.applySetupStatusSync(message)
                }

                rpcTask.cancel()

                guard !Task.isCancelled else { return }

                // Stream ended — daemon may have restarted.
                self?.state = .registered
                self?.setupPhase = .unknown

                // Back off before reconnecting.
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Stop watching the gRPC stream.
    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: - Internal

    /// Apply a setup status update. Called from MainActor-isolated stream handlers.
    private func applySetupStatusSync(_ status: Arcbox_V1_SetupStatus) {
        dnsResolverInstalled = status.dnsResolverInstalled
        dockerSocketLinked = status.dockerSocketLinked
        routeInstalled = status.routeInstalled
        vmRunning = status.vmRunning
        dockerToolsInstalled = status.dockerToolsInstalled
        setupMessage = status.message

        switch status.phase {
        case .unspecified:  setupPhase = .unknown
        case .initializing: setupPhase = .initializing
        case .downloadingAssets: setupPhase = .downloadingAssets
        case .assetsReady:  setupPhase = .assetsReady
        case .vmStarting:   setupPhase = .vmStarting
        case .vmReady:      setupPhase = .vmReady
        case .networkReady: setupPhase = .networkReady
        case .ready:        setupPhase = .ready
        case .degraded:     setupPhase = .degraded
        case .cleaningUp:   setupPhase = .unknown
        case .UNRECOGNIZED: setupPhase = .unknown
        }

        // Any message from the stream means the daemon is alive.
        if state != .running {
            state = .running
            ClientLog.daemon.info("Daemon is running (gRPC stream connected)")
        }
    }
}

/// Runs `<binary> --version` and returns the trimmed stdout (e.g. "arcbox-helper 0.3.1").
/// Returns nil if the binary doesn't exist or the command fails.
private func binaryVersion(_ path: String) -> String? {
    guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}
