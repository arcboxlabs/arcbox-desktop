import Foundation
import Observation
import OSLog
@preconcurrency import Sentry

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
/// - Phase 2: Non-critical steps (helper, CLI, Docker, runtime) run as
///   fire-and-forget background tasks. The critical daemon path
///   (enableDaemon -> initClients) blocks readiness.
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

    /// Whether a retry is possible (i.e., startup has failed and not currently running).
    public var canRetry: Bool {
        if case .failed = phase { return true }
        return false
    }

    // Dependencies
    private let bootAssetManager: BootAssetManager
    private let helperManager: HelperManager
    private let daemonManager: DaemonManager
    private let dockerToolSetupManager: DockerToolSetupManager
    private let onClientsNeeded: @MainActor () throws -> Void

    private static let signposter = OSSignposter(
        subsystem: "com.arcboxlabs.desktop", category: "startup")

    /// Prevents concurrent startup runs from interleaving.
    private var isStarting = false

    /// Handles for non-critical background tasks, cancelled on critical failure.
    private var nonCriticalTasks: [Task<Void, Never>] = []

    public init(
        bootAssetManager: BootAssetManager,
        helperManager: HelperManager,
        daemonManager: DaemonManager,
        dockerToolSetupManager: DockerToolSetupManager,
        onClientsNeeded: @escaping @MainActor () throws -> Void
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
    /// Guarded against concurrent execution: if already running, subsequent
    /// calls are no-ops.
    public func start() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // Cancel leftover non-critical tasks from a previous run.
        cancelNonCriticalTasks()

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

        // Phase 2: Start non-critical steps as fire-and-forget background tasks.
        // They don't block readiness — only the critical path gates .completed.
        launchNonCriticalSteps()

        // Phase 2: Critical daemon path (sequential, blocks readiness).
        await runDaemonPath()

        // Mark completed as soon as critical path finishes.
        // Non-critical tasks continue in the background.
        if case .failed = phase {
            cancelNonCriticalTasks()
            return
        }
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

    /// Launch non-critical steps as fire-and-forget background tasks.
    /// Failures are recorded in stepStatuses but do not block readiness
    /// or abort the startup sequence.
    private func launchNonCriticalSteps() {
        nonCriticalTasks = [
            Task {
                await self.runStep(.setupHelper) {
                    try await self.performSetupHelper()
                }
            },
            Task {
                await self.runStep(.cliSetup) {
                    let cli = try CLIRunner()
                    try await cli.run(arguments: ["setup", "install"])
                }
            },
            Task {
                await self.runStep(.dockerToolSetup) {
                    await self.dockerToolSetupManager.installAndEnable()
                }
            },
            Task {
                await self.runStep(.seedRuntime) {
                    await self.bootAssetManager.seedRuntimeBinaries()
                    await self.bootAssetManager.seedAgentBinary()
                }
            },
        ]
    }

    /// Cancel all non-critical background tasks (e.g., on critical failure).
    private func cancelNonCriticalTasks() {
        for task in nonCriticalTasks {
            task.cancel()
        }
        nonCriticalTasks = []
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
            try self.onClientsNeeded()
        }

        // After daemon is fully ready, install host routes for container
        // subnets via the vmnet bridge. This enables `curl http://172.17.0.2/`
        // from the host without -p port mapping.
        Task {
            await self.installContainerRoutes()
        }
    }

    // MARK: - Container Route Installation

    private static let containerSubnet = "172.16.0.0/12"
    private static let maxRouteRetries = 10
    private static let retryInterval: Duration = .seconds(2)

    /// The bridge interface we installed a route on, tracked for cleanup.
    private var installedRouteInterface: String?

    /// Installs a host route for container subnets via the vmnet bridge interface.
    /// Retries until the bridge interface appears or max attempts are exhausted.
    private func installContainerRoutes() async {
        for attempt in 1...Self.maxRouteRetries {
            guard let bridgeIface = findBridgeInterface() else {
                ClientLog.helper.debug("Route attempt \(attempt)/\(Self.maxRouteRetries): bridge interface not found, retrying")
                try? await Task.sleep(for: Self.retryInterval)
                continue
            }

            do {
                try await helperManager.addRouteInterface(
                    subnet: Self.containerSubnet,
                    iface: bridgeIface
                )
                installedRouteInterface = bridgeIface
                ClientLog.helper.info("Route installed: \(Self.containerSubnet) -interface \(bridgeIface, privacy: .public) (attempt \(attempt))")
                return
            } catch {
                ClientLog.helper.warning("Route attempt \(attempt) failed: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: Self.retryInterval)
            }
        }
        ClientLog.helper.error("Failed to install container route after \(Self.maxRouteRetries) attempts")
    }

    /// Removes the host route installed by installContainerRoutes.
    /// Called on app shutdown.
    func removeContainerRoutes() async {
        guard let iface = installedRouteInterface else { return }
        do {
            try await helperManager.removeRouteInterface(
                subnet: Self.containerSubnet,
                iface: iface
            )
            ClientLog.helper.info("Route removed: \(Self.containerSubnet) -interface \(iface, privacy: .public)")
        } catch {
            ClientLog.helper.warning("Route cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
        installedRouteInterface = nil
    }

    /// Finds the vmnet bridge interface by checking bridge100-109.
    private func findBridgeInterface() -> String? {
        for i in 100..<110 {
            let name = "bridge\(i)"
            var ifr = ifreq()
            name.withCString { cstr in
                withUnsafeMutablePointer(to: &ifr.ifr_name) { ptr in
                    _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr)
                }
            }
            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            if ioctl(fd, UInt(0xc0206911) /* SIOCGIFFLAGS */, &ifr) == 0 {
                return name
            }
        }
        return nil
    }

    // MARK: - Helper Setup

    /// Migrated from ArcBoxApp.setupHelper() — registers the privileged helper
    /// and performs Docker socket, CLI tools, and DNS resolver setup.
    /// Throws on registration failure so runStep can mark .failed.
    private func performSetupHelper() async throws {
        do {
            try await helperManager.registerWithRetry()
        } catch {
            throw StartupError.stepFailed(
                "Helper registration failed: \(error.localizedDescription)")
        }

        let socketPath = DaemonManager.dockerSocketPath
        let bundlePath = Bundle.main.bundleURL.path

        // Each operation is independent — run separately so one failure
        // does not cancel the others.
        do {
            try await helperManager.setupDockerSocket(socketPath: socketPath)
        } catch {
            ClientLog.helper.error("setupDockerSocket failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try await helperManager.installCLITools(appBundlePath: bundlePath)
        } catch {
            ClientLog.helper.error("installCLITools failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try await helperManager.setupDNSResolver()
        } catch {
            ClientLog.helper.error("setupDNSResolver failed: \(error.localizedDescription, privacy: .public)")
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
            if step.isCritical {
                phase = .failed(step: step, message: message)
            }
            return false
        }
    }
}
