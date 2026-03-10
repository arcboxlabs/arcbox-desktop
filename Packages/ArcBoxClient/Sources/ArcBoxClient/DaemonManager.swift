import Foundation
import Observation
import ServiceManagement

/// Daemon connection state derived from SMAppService registration + reachability.
public enum DaemonState: Sendable, Equatable {
    case stopped        // Not registered with launchd
    case starting       // Enable in progress
    case stopping       // Disable in progress
    case registered     // Registered but not yet reachable
    case running        // Registered and /_ping reachable
    case error(String)

    public var isRunning: Bool { self == .running }
}

/// Manages the arcbox daemon lifecycle via SMAppService (LaunchAgent).
///
/// The daemon binary is bundled in the app at `Contents/Helpers/io.arcbox.desktop.daemon`
/// and managed by launchd. `KeepAlive` in the plist ensures automatic restart on crash.
@Observable
@MainActor
public final class DaemonManager {
    /// Current daemon state.
    public private(set) var state: DaemonState = .stopped

    /// Whether the daemon is reachable via Docker socket.
    public private(set) var isReachable: Bool = false

    /// Last error message from enable/disable operations.
    public private(set) var errorMessage: String?

    /// Path to the Docker-compatible socket used for health checks and DockerClient.
    public nonisolated static let dockerSocketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.arcbox/run/docker.sock"
    }()

    private nonisolated static let plistName = "io.arcbox.desktop.daemon.plist"

    private nonisolated var service: SMAppService {
        SMAppService.agent(plistName: Self.plistName)
    }

    private var monitorTask: Task<Void, Never>?

    public init() {}

    // MARK: - State

    /// Refresh registration status from SMAppService and derive state.
    public func refresh() {
        let status = service.status
        if isReachable {
            state = .running
        } else if status == .enabled {
            state = .registered
        } else {
            state = .stopped
        }
    }

    // MARK: - Daemon Lifecycle

    /// Register the daemon with launchd and wait for it to become reachable.
    public func enableDaemon() async {
        // Fast path: daemon already reachable (subsequent launches)
        await checkReachability()
        if isReachable {
            state = .running
            return
        }

        errorMessage = nil
        state = .starting

        // Ensure log directory exists (launchd fails if it can't create stdout/stderr paths)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logDir = "\(home)/.arcbox/logs"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        let status = service.status
        print("[DaemonManager] Current SMAppService status: \(status)")

        do {
            try service.register()
            print("[DaemonManager] Service registered successfully")
        } catch {
            print("[DaemonManager] Failed to register: \(error)")
            errorMessage = error.localizedDescription
            state = .error("Failed to register daemon: \(error.localizedDescription)")
            return
        }

        // Poll for reachability (up to 10 seconds)
        for i in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            await checkReachability()
            if isReachable {
                print("[DaemonManager] Daemon reachable after \(i + 1) checks")
                break
            }
        }

        if !isReachable {
            print("[DaemonManager] Daemon registered but not reachable after 10s")
            errorMessage = "Daemon registered but not responding. Check Console.app for launch errors."
            state = .registered
        } else {
            state = .running
        }
    }

    /// Unregister the daemon from launchd.
    public func disableDaemon() async {
        errorMessage = nil
        state = .stopping

        do {
            try await service.unregister()
        } catch {
            errorMessage = error.localizedDescription
        }

        // Wait up to 5 seconds for daemon to stop
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            await checkReachability()
            if !isReachable { break }
        }

        refresh()
    }

    // MARK: - Health Monitoring

    /// Start periodic reachability monitoring (every 3 seconds).
    ///
    /// Automatically updates `state` and `isReachable`.
    public func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkReachability()
                self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Stop periodic monitoring.
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Reachability Check

    /// Check if the daemon is reachable by sending `GET /_ping` to the Docker socket.
    @discardableResult
    public func checkReachability() async -> Bool {
        let reachable = await Task.detached { self.healthCheck() }.value
        isReachable = reachable
        return reachable
    }

    /// Check if the daemon is reachable via raw POSIX socket to `/_ping`.
    public nonisolated func healthCheck() -> Bool {
        let path = Self.dockerSocketPath

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else { return false }

        _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            pathBytes.withUnsafeBufferPointer { buf in
                memcpy(sunPath, buf.baseAddress!, buf.count)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let request = "GET /_ping HTTP/1.0\r\nHost: localhost\r\n\r\n"
        let written = request.withCString { cstr in
            write(fd, cstr, strlen(cstr))
        }
        guard written > 0 else { return false }

        var buffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = read(fd, &buffer, buffer.count - 1)
        guard bytesRead > 0 else { return false }

        let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        return response.contains("200")
    }
}
