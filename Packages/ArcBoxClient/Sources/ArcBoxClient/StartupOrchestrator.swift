import Foundation
import OSLog
import Observation
@preconcurrency import Sentry

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

        // Step 1: Install privileged helper (one-time, macOS prompts for admin).
        // Non-critical: daemon works without it, just no DNS/socket integration.
        await runStep(.installHelper) {
            await self.daemonManager.installHelper()
        }

        // Step 2: Register daemon with launchd.
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

        // Step 3: Connect gRPC and start watching setup status.
        //
        // Two-phase approach:
        //   Phase 1 — normal poll (30 s): gives the daemon its full startup window.
        //   Phase 2 — recovery:  force unregister+register, then poll again (30 s).
        //
        // Phase 2 exists because Xcode "Replace" sends SIGKILL, so
        // `applicationShouldTerminate` / `disableDaemon()` never runs.  The
        // daemon stays `.enabled` in launchd but the actual process may be
        // dead or stuck in a throttled restart cycle.
        //
        // ⚠️ REGRESSION GUARD — the recovery MUST happen only AFTER the full
        // phase-1 timeout.  Moving the force-reregister into `enableDaemon()`
        // or running it earlier would regress a known bug where SwiftUI
        // `.task` re-entrancy triggers multiple `enableDaemon()` calls that
        // each kill the daemon before it finishes initializing.
        let connectOK = await runStep(.connectAndWatch) {
            let client = try self.onClientsNeeded()
            self.daemonManager.connectAndWatch(client: client)

            // Phase 1: normal poll — daemon may be starting up; give it the
            // full timeout before assuming it's dead.
            for _ in 0..<StartupConstants.daemonPollMaxAttempts {
                if self.daemonManager.state.isRunning { break }
                try await Task.sleep(for: StartupConstants.daemonPollInterval)
            }

            if self.daemonManager.state.isRunning { return }

            // Phase 2: recovery — daemon is registered but confirmed
            // unreachable after the full poll window.  Force re-register to
            // get launchd to spawn a fresh daemon process, then poll again.
            ClientLog.startup.warning(
                "Daemon unreachable after \(Int(StartupConstants.daemonPollTimeout.components.seconds))s, attempting force re-register recovery"
            )
            await self.daemonManager.forceReregisterDaemon()

            if case .error = self.daemonManager.state {
                throw StartupError.stepFailed("Force re-register failed")
            }

            self.daemonManager.connectAndWatch(client: client)

            for _ in 0..<StartupConstants.daemonPollMaxAttempts {
                if self.daemonManager.state.isRunning { break }
                try await Task.sleep(for: StartupConstants.daemonPollInterval)
            }

            if !self.daemonManager.state.isRunning {
                let totalSeconds = Int(StartupConstants.daemonPollTimeout.components.seconds) * 2
                throw StartupError.stepFailed(
                    "Daemon unreachable after force re-register recovery (\(totalSeconds)s total)")
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
                "\(step.label, privacy: .public) failed after \(elapsedMs, privacy: .public)ms: \(message, privacy: .private)"
            )
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
