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

    /// The case name alone. `error`'s message varies per user and per failure, so it is
    /// left out: this is for diagnostics that must stay groupable.
    public var label: String {
        switch self {
        case .stopped: "stopped"
        case .starting: "starting"
        case .stopping: "stopping"
        case .registered: "registered"
        case .running: "running"
        case .error: "error"
        }
    }
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
    /// Fatal startup error; the daemon gave up. See `setupMessage` for details.
    case failed

    /// Whether the profile's Docker API socket is expected
    /// to be available at this phase. This is true once the daemon has finished
    /// its full setup or is running in a degraded state.
    ///
    /// Note: this is distinct from `dockerSocketLinked`, which tracks the CLI
    /// convenience symlink at `/var/run/docker.sock`.
    public var isDockerReady: Bool {
        self == .ready || self == .degraded
    }
}
