import Foundation

/// Daemon connection state derived from SMAppService registration + gRPC stream.
public enum DaemonState: Sendable, Equatable {
    case stopped  // Not registered with launchd
    case starting  // Enable in progress
    case stopping  // Disable in progress
    case registered  // Registered but gRPC stream not connected yet
    case running  // gRPC stream connected, daemon alive
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
    case cleaningUp
    case failed

    /// Whether the Docker API socket (`~/.arcbox/run/docker.sock`) is expected
    /// to be available at this phase. This is true once the daemon has finished
    /// its full setup or is running in a degraded state.
    ///
    /// Note: this is distinct from `dockerSocketLinked`, which tracks the CLI
    /// convenience symlink at `/var/run/docker.sock`.
    public var isDockerReady: Bool {
        self == .ready || self == .degraded
    }
}
