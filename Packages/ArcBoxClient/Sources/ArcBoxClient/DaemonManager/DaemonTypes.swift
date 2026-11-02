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

    /// Whether host startup has finished, so Machine operations are available. Docker
    /// needs the System runtime as well; see ``DaemonManager/isDockerReady``.
    public var isHostReady: Bool {
        self == .ready || self == .degraded
    }
}

/// Readiness of the System VM and the Docker runtime inside it, mirroring the proto
/// `SystemRuntimeStatus.State`. Reported independently of the host phase: a daemon
/// reaches host `READY` first and boots the System VM afterwards.
public enum SystemRuntimeState: Sendable, Equatable {
    /// The daemon predates `system_runtime`. Its host `READY` meant Docker was up.
    case notReported
    case unknown
    /// System VM autostart is disabled; Docker never starts.
    case disabled
    /// The System VM waits for a component the daemon installs on demand: the QEMU build
    /// that emulates it on a Mac without hardware virtualization.
    case downloading
    /// Assets and runtime binaries are being prepared.
    case starting
    case vmStarting
    /// The guest agent answered; Docker is still starting.
    case vmReady
    case ready
    /// Startup failed. The daemon keeps running; see `systemRuntimeReason`.
    case failed

    init(_ state: Arcbox_V1_SystemRuntimeStatus.State) {
        switch state {
        case .disabled: self = .disabled
        case .downloading: self = .downloading
        case .starting: self = .starting
        case .vmStarting: self = .vmStarting
        case .vmReady: self = .vmReady
        case .ready: self = .ready
        case .failed: self = .failed
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}

/// Why Docker is not coming up on its own, once the host is ready.
public enum SystemRuntimeIssue: Sendable, Equatable {
    /// This Mac has no hardware virtualization and the daemon has no backend that runs
    /// without it. Restarting the daemon does not change that.
    case hardwareVirtualizationUnavailable
    /// System startup failed; restarting the daemon retries it.
    case failed(reason: String)
    case disabled(reason: String)
}

/// A runtime component the daemon installs before the System VM can boot, such as the
/// QEMU build software emulation needs. One at a time; the System runtime's reason names
/// the component and version.
public struct RuntimeDownloadProgress: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        case transferring
        case verifying
        case installing
        /// A transfer failed; the daemon retries on its own, and its reason says when.
        case waitingToRetry
    }

    public var stage: Stage
    /// Bytes on disk, a resumed partial download included. Not monotonic: a resume that
    /// fails verification starts again from zero.
    public var downloadedBytes: Int64
    /// `nil` while the size is unknown, which the daemon reports as 0.
    public var totalBytes: Int64?
}

extension RuntimeDownloadProgress {
    /// `nil` for a stage this client does not know; the progress detail then shows the
    /// daemon's reason alone. The component is not kept: the reason names it.
    init?(_ download: Arcbox_V1_ComponentDownload) {
        switch download.stage {
        case .transferring: stage = .transferring
        case .verifying: stage = .verifying
        case .installing: stage = .installing
        case .waitingToRetry: stage = .waitingToRetry
        case .unspecified, .UNRECOGNIZED: return nil
        }
        downloadedBytes = Int64(clamping: download.downloadedBytes)
        totalBytes = download.totalBytes == 0 ? nil : Int64(clamping: download.totalBytes)
    }
}
