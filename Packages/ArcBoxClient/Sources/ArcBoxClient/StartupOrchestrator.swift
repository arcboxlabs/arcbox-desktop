import Foundation
import Observation
import OSLog
@preconcurrency import Sentry

// MARK: - Startup Constants

/// Centralized timing constants for the startup sequence.
public enum StartupConstants {
    public static let daemonPollTimeout: Duration = .seconds(10)
    public static let daemonPollInterval: Duration = .milliseconds(500)
    public static let daemonPollMaxAttempts = 20
    public static let daemonStopTimeout: Duration = .seconds(5)
    public static let daemonStopPollInterval: Duration = .milliseconds(500)
    public static let daemonStopMaxAttempts = 10
}

// MARK: - Startup Step

/// Each discrete step in the startup sequence.
///
/// The daemon handles all provisioning (boot assets, runtime binaries, Docker
/// tools). The desktop app only needs to register the LaunchAgent and connect
/// the gRPC stream.
public enum StartupStep: Int, CaseIterable, Sendable, Identifiable {
    case enableDaemon = 0
    case connectAndWatch = 1

    public var id: Int { rawValue }

    /// Human-readable label shown in the progress UI.
    public var label: String {
        switch self {
        case .enableDaemon:    return "Starting daemon"
        case .connectAndWatch: return "Connecting to daemon"
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
}

// MARK: - Internal Errors

/// Errors thrown by step bodies to signal failure.
private enum StartupError: LocalizedError {
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .stepFailed(let msg): return msg
        }
    }
}

// MARK: - Startup Orchestrator

/// Coordinates the app startup sequence with step tracking, error propagation,
/// and retry support.
///
/// The daemon self-provisions all assets. The desktop app is a pure display
/// layer: register the LaunchAgent, then connect gRPC and watch setup status.
@Observable
@MainActor
public final class StartupOrchestrator {
    /// Overall startup phase.
    public private(set) var phase: StartupPhase = .idle

    /// Per-step status for UI display.
    public private(set) var stepStatuses: [StartupStep: StepStatus]

    /// Normalized progress [0, 1] based on completed/total steps.
    public var progress: Double {
        let total = Double(StartupStep.allCases.count)
        let done = Double(
            stepStatuses.values.filter {
                if case .completed = $0 { return true }
                if case .skipped = $0 { return true }
                return false
            }.count
        )
        return done / total
    }

    /// Whether all steps have completed successfully.
    public var isReady: Bool { phase == .completed }

    /// Whether a retry is possible.
    public var canRetry: Bool {
        if case .failed = phase { return true }
        return false
    }

    // Dependencies
    private let daemonManager: DaemonManager
    private let onClientsNeeded: @MainActor () throws -> ArcBoxClient

    private static let signposter = OSSignposter(
        subsystem: "com.arcboxlabs.desktop", category: "startup")

    /// Prevents concurrent startup runs from interleaving.
    private var isStarting = false

    public init(
        daemonManager: DaemonManager,
        onClientsNeeded: @escaping @MainActor () throws -> ArcBoxClient
    ) {
        self.daemonManager = daemonManager
        self.onClientsNeeded = onClientsNeeded

        var statuses: [StartupStep: StepStatus] = [:]
        for step in StartupStep.allCases {
            statuses[step] = .pending
        }
        self.stepStatuses = statuses
    }

    // MARK: - Public API

    /// Run the full startup sequence.
    ///
    /// Safe to call multiple times — resets state on each invocation.
    /// Guarded against concurrent execution.
    @available(macOS 15.0, *)
    public func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        for step in StartupStep.allCases {
            stepStatuses[step] = .pending
        }

        // Step 1: Register daemon with launchd.
        let daemonOK = await runStep(.enableDaemon) {
            await self.daemonManager.enableDaemon()
            if case .error(let msg) = self.daemonManager.state {
                throw StartupError.stepFailed(msg)
            }
        }

        guard daemonOK else {
            stepStatuses[.connectAndWatch] = .skipped
            return
        }

        // Step 2: Connect gRPC and start watching setup status.
        let connectOK = await runStep(.connectAndWatch) {
            let client = try self.onClientsNeeded()
            self.daemonManager.connectAndWatch(client: client)

            // Wait for the first status message (daemon is alive).
            for _ in 0..<StartupConstants.daemonPollMaxAttempts {
                try? await Task.sleep(for: StartupConstants.daemonPollInterval)
                if self.daemonManager.state.isRunning {
                    break
                }
            }

            if !self.daemonManager.state.isRunning {
                throw StartupError.stepFailed(
                    "Daemon registered but gRPC stream not connected after \(Int(StartupConstants.daemonPollTimeout.components.seconds))s")
            }
        }

        guard connectOK else { return }
        phase = .completed
    }

    /// Retry the startup sequence after a failure.
    @available(macOS 15.0, *)
    public func retry() async {
        await start()
    }

    // MARK: - Step Runner

    @discardableResult
    private func runStep(
        _ step: StartupStep,
        body: @MainActor () async throws -> Void
    ) async -> Bool {
        stepStatuses[step] = .running
        phase = .running(step: step)

        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval(
            "Startup Step", id: signpostID, "\(step.label, privacy: .public)")
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            try await body()
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            ClientLog.startup.info(
                "\(step.label, privacy: .public) completed in \(elapsedMs, privacy: .public)ms")
            Self.signposter.endInterval("Startup Step", state)
            stepStatuses[step] = .completed
            return true
        } catch {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let message = error.localizedDescription
            ClientLog.startup.error(
                "\(step.label, privacy: .public) failed after \(elapsedMs, privacy: .public)ms: \(message, privacy: .public)")
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: step.label, key: "startup_step")
            }
            Self.signposter.endInterval("Startup Step", state)
            stepStatuses[step] = .failed(message)
            phase = .failed(step: step, message: message)
            return false
        }
    }
}
