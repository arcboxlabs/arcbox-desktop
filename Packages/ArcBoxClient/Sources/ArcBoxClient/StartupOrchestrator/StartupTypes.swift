import Foundation

// MARK: - Startup Constants

/// Centralized timing constants for the startup sequence.
public enum StartupConstants {
    public static let daemonPollTimeout: Duration = .seconds(30)
    public static let daemonPollInterval: Duration = .milliseconds(500)
    public static let daemonPollMaxAttempts = 60
    public static let daemonStopTimeout: Duration = .seconds(5)
    public static let daemonStopPollInterval: Duration = .milliseconds(500)
    public static let daemonStopMaxAttempts = 10
}

// MARK: - Startup Step

/// Each discrete step in the startup sequence.
///
/// The daemon handles all provisioning (boot assets, runtime binaries, Docker
/// tools). The desktop app registers the helper (privileged, one-time),
/// starts the daemon LaunchAgent, and connects the gRPC stream.
public enum StartupStep: Int, CaseIterable, Sendable, Identifiable {
    case installHelper = 0
    case enableDaemon = 1
    case connectAndWatch = 2

    public var id: Int { rawValue }

    /// Human-readable label shown in the progress UI.
    public var label: String {
        switch self {
        case .installHelper: return "Installing helper service"
        case .enableDaemon: return "Starting daemon"
        case .connectAndWatch: return "Connecting to daemon"
        }
    }

    /// Short explanation shown under the step label in the startup UI.
    public var detail: String? {
        switch self {
        case .installHelper:
            return "Required for /usr/local/bin/docker and DNS integration"
        case .enableDaemon, .connectAndWatch:
            return nil
        }
    }
}

// MARK: - Step Status

/// Status of an individual startup step.
public enum StepStatus: Sendable, Equatable {
    case pending
    case running
    case completed
    case skipped
    case failed(String)
}

// MARK: - Startup Phase

/// Overall startup phase — drives the top-level UI state.
public enum StartupPhase: Sendable, Equatable {
    case idle
    case running(step: StartupStep)
    case completed
    case failed(step: StartupStep, message: String)
    /// Non-recoverable error (e.g. missing entitlements). User must quit.
    case fatalError(message: String)
}
