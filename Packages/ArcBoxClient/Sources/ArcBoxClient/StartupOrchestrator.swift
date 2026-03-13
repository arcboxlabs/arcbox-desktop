import Foundation
import Observation
import ServiceManagement

// MARK: - Startup Constants

/// Centralized timing constants for the startup sequence.
/// Eliminates magic numbers scattered across DaemonManager, HelperManager, etc.
public enum StartupConstants {
    public static let daemonPollTimeout: Duration = .seconds(10)
    public static let daemonPollInterval: Duration = .milliseconds(500)
    public static let daemonPollMaxAttempts = 20
    public static let healthMonitorInterval: Duration = .seconds(3)
    public static let helperApprovalTimeout: Duration = .seconds(120)
    public static let helperApprovalPollInterval: Duration = .seconds(2)
    public static let helperApprovalMaxAttempts = 60
    public static let xpcTimeout: TimeInterval = 10
    public static let daemonStopTimeout: Duration = .seconds(5)
    public static let daemonStopPollInterval: Duration = .milliseconds(500)
    public static let daemonStopMaxAttempts = 10
    public static let updateCheckDelay: Duration = .seconds(5)
}

// MARK: - Startup Step

/// Each discrete step in the startup sequence.
public enum StartupStep: Int, CaseIterable, Sendable, Identifiable {
    case ensureAssets = 0
    case setupHelper = 1
    case cliSetup = 2
    case dockerToolSetup = 3
    case seedRuntime = 4
    case enableDaemon = 5   // Includes startMonitoring
    case initClients = 6

    public var id: Int { rawValue }

    /// Human-readable label shown in the progress UI.
    public var label: String {
        switch self {
        case .ensureAssets:     return "Preparing boot assets"
        case .setupHelper:     return "Registering privileged helper"
        case .cliSetup:        return "Installing CLI tools"
        case .dockerToolSetup: return "Setting up Docker tools"
        case .seedRuntime:     return "Seeding runtime binaries"
        case .enableDaemon:    return "Starting daemon"
        case .initClients:     return "Connecting to daemon"
        }
    }

    /// Whether failure of this step should abort the startup sequence.
    public var isCritical: Bool {
        switch self {
        case .ensureAssets, .enableDaemon, .initClients: return true
        default: return false
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
/// Steps are organized into phases:
/// - Phase 1: `ensureAssets` (critical, blocks everything)
/// - Phase 2: Non-critical steps (helper, CLI, Docker, runtime) run in parallel
///   with the critical daemon path (enableDaemon -> initClients).
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

    /// Whether all critical steps have completed successfully.
    public var isReady: Bool { phase == .completed }

    /// Whether a retry is possible (i.e., startup has failed).
    public var canRetry: Bool {
        if case .failed = phase { return true }
        return false
    }

    // Dependencies
    private let bootAssetManager: BootAssetManager
    private let helperManager: HelperManager
    private let daemonManager: DaemonManager
    private let dockerToolSetupManager: DockerToolSetupManager
    private let onClientsNeeded: @MainActor () -> Void

    public init(
        bootAssetManager: BootAssetManager,
        helperManager: HelperManager,
        daemonManager: DaemonManager,
        dockerToolSetupManager: DockerToolSetupManager,
        onClientsNeeded: @escaping @MainActor () -> Void
    ) {
        self.bootAssetManager = bootAssetManager
        self.helperManager = helperManager
        self.daemonManager = daemonManager
        self.dockerToolSetupManager = dockerToolSetupManager
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
    /// Already-cached steps (e.g., boot assets) will complete instantly.
    public func start() async {
        // Reset all step statuses.
        for step in StartupStep.allCases {
            stepStatuses[step] = .pending
        }

        // Phase 1: Ensure boot assets (critical, blocks all subsequent steps).
        let assetsOK = await runStep(.ensureAssets) {
            await self.bootAssetManager.ensureAssets()
            if case .error(let msg) = self.bootAssetManager.state {
                throw StartupError.stepFailed(msg)
            }
        }

        guard assetsOK else {
            for step in StartupStep.allCases where step != .ensureAssets {
                stepStatuses[step] = .skipped
            }
            return
        }

        // Phase 2: Run non-critical steps and critical daemon path in parallel.
        // Task.init inherits @MainActor from the enclosing context, avoiding
        // the `sending` parameter conflict that withTaskGroup would trigger.
        let groupA = Task { await self.runNonCriticalSteps() }
        let groupB = Task { await self.runDaemonPath() }
        await groupA.value
        await groupB.value

        // Only mark completed if no critical step failed.
        if case .failed = phase { return }
        phase = .completed
    }

    /// Retry the startup sequence after a failure.
    ///
    /// Performs a full restart — already-cached operations (boot assets,
    /// runtime binaries) will complete instantly.
    public func retry() async {
        await start()
    }

    // MARK: - Step Groups

    /// Non-critical steps that run in parallel. Failures are recorded but
    /// do not abort the startup sequence.
    private func runNonCriticalSteps() async {
        let t1 = Task {
            await self.runStep(.setupHelper) {
                await self.performSetupHelper()
            }
        }
        let t2 = Task {
            await self.runStep(.cliSetup) {
                if let cli = try? CLIRunner() {
                    try? await cli.run(arguments: ["setup", "install"])
                }
            }
        }
        let t3 = Task {
            await self.runStep(.dockerToolSetup) {
                await self.dockerToolSetupManager.installAndEnable()
            }
        }
        let t4 = Task {
            await self.runStep(.seedRuntime) {
                await self.bootAssetManager.seedRuntimeBinaries()
                await self.bootAssetManager.seedAgentBinary()
            }
        }
        await t1.value
        await t2.value
        await t3.value
        await t4.value
    }

    /// Critical daemon startup: monitoring -> enable -> init clients.
    /// Each step must succeed for the next to proceed.
    private func runDaemonPath() async {
        let daemonOK = await runStep(.enableDaemon) {
            self.daemonManager.startMonitoring()
            await self.daemonManager.enableDaemon()
            if case .error(let msg) = self.daemonManager.state {
                throw StartupError.stepFailed(msg)
            }
        }

        guard daemonOK else {
            stepStatuses[.initClients] = .skipped
            return
        }

        await runStep(.initClients) {
            self.onClientsNeeded()
        }
    }

    // MARK: - Helper Setup

    /// Migrated from ArcBoxApp.setupHelper() — registers the privileged helper
    /// and performs Docker socket, CLI tools, and DNS resolver setup.
    private func performSetupHelper() async {
        do {
            try await helperManager.registerWithRetry()
        } catch {
            print("[Helper] registration failed: \(error)")
            return
        }

        let socketPath = DaemonManager.dockerSocketPath
        let bundlePath = Bundle.main.bundleURL.path

        // Each operation is independent — run separately so one failure
        // does not cancel the others.
        do {
            try await helperManager.setupDockerSocket(socketPath: socketPath)
        } catch {
            print("[Helper] setupDockerSocket failed: \(error)")
        }

        do {
            try await helperManager.installCLITools(appBundlePath: bundlePath)
        } catch {
            print("[Helper] installCLITools failed: \(error)")
        }

        do {
            try await helperManager.setupDNSResolver()
        } catch {
            print("[Helper] setupDNSResolver failed: \(error)")
        }
    }

    // MARK: - Step Runner

    /// Execute a step body with automatic status tracking.
    ///
    /// Updates `stepStatuses` and (for critical steps) `phase`.
    /// Returns `true` if the step completed successfully.
    @discardableResult
    private func runStep(
        _ step: StartupStep,
        body: @MainActor () async throws -> Void
    ) async -> Bool {
        stepStatuses[step] = .running
        if step.isCritical {
            phase = .running(step: step)
        }

        do {
            try await body()
            stepStatuses[step] = .completed
            return true
        } catch {
            let message = error.localizedDescription
            stepStatuses[step] = .failed(message)
            if step.isCritical {
                phase = .failed(step: step, message: message)
            }
            return false
        }
    }
}
