import Foundation
import OSLog
import Observation

// MARK: - Internal Errors

/// Errors thrown by step bodies to signal failure.
///
/// Deliberately not `private`: a file-scoped private type has no nameable parent context,
/// so the runtime renders it as `ArcBoxClient.(unknown context at $1035…).StartupError`
/// with a live address in it. That is the bridged `NSError` domain, and it is what the
/// crash reporter groups by, so every launch filed its startup failures under a brand new
/// issue — 45 of them for two distinct failures.
enum StartupError: LocalizedError {
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

    /// Whether the daemon has also finished preparing the shared runtime.
    public var isRuntimeReady: Bool { isReady && daemonManager.setupPhase.isDockerReady }

    /// Current daemon-provided setup detail for progress UI.
    public var setupMessage: String { daemonManager.setupMessage }

    /// Fatal runtime setup error reported after the gRPC connection succeeds.
    public var runtimeFailureMessage: String? {
        guard isReady, case .error(let message) = daemonManager.state else { return nil }
        return message
    }

    /// Whether a retry is possible.
    public var canRetry: Bool {
        if case .failed = phase { return true }
        return runtimeFailureMessage != nil
    }

    // Dependencies
    private let daemonManager: DaemonManager
    private let onClientsNeeded: @MainActor () throws -> ArcBoxClient

    private static let signposter = OSSignposter(
        subsystem: "com.arcboxlabs.desktop", category: "startup")

    /// Owns the active run so app termination can cancel retries as well as
    /// the initial startup task.
    private var startupTask: Task<Void, Never>?
    private var isTerminating = false

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
    ///
    /// - Parameter allowingAdministratorPrompt: `true` only after the user has
    ///   explicitly chosen to continue to the macOS administrator prompt.
    @available(macOS 15.0, *)
    public func start(allowingAdministratorPrompt: Bool = false) async {
        guard !isTerminating else { return }
        if let startupTask {
            await startupTask.value
            return
        }

        let task = Task {
            await runStartup(allowingAdministratorPrompt: allowingAdministratorPrompt)
            startupTask = nil
        }
        startupTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Permanently stops startup work before app shutdown continues.
    public func cancelForTermination() async {
        isTerminating = true
        startupTask?.cancel()
        await startupTask?.value
    }

    private func runStartup(allowingAdministratorPrompt: Bool) async {
        guard !isCancellationRequested else { return }

        for step in StartupStep.allCases {
            stepStatuses[step] = .pending
        }

        // Step 1: Install / upgrade the privileged helper (macOS prompts for admin).
        // Critical for /usr/local/bin/docker* symlinks, DNS resolver, and the
        // docker.sock convenience link. Failures used to be swallowed, leaving
        // an ancient helper on disk and no CLI tools on PATH.
        let helperOK = await runStep(.installHelper) {
            try await self.daemonManager.installHelper(
                allowingAdministratorPrompt: allowingAdministratorPrompt
            )
        }

        guard !isCancellationRequested else { return }
        guard helperOK else {
            stepStatuses[.enableDaemon] = .skipped
            stepStatuses[.connectAndWatch] = .skipped
            return
        }

        // Pre-check: verify daemon binary signature and entitlements.
        //
        // The daemon requires Developer ID signing — restricted entitlements
        // (com.apple.security.virtualization, com.apple.security.hypervisor,
        // com.apple.vm.networking) are only accepted by AMFI when signed with
        // Developer ID, not Apple Development. Without these, launchd refuses
        // to exec with OS_REASON_EXEC and the daemon silently crash-loops.
        //
        // This applies to ALL builds including Debug. The embed step
        // (cargo xtask macos embed) resolves the Developer ID certificate
        // independently of Xcode's CODE_SIGN_IDENTITY for this reason.
        //
        // Strict verification is intentional — if this blocks your local
        // build, ensure the daemon is signed with Developer ID:
        //   make -C ../arcbox sign-daemon
        let verifyError = await daemonManager.verifyDaemonBinary()
        guard !isCancellationRequested else {
            phase = .idle
            return
        }
        if let verifyError {
            ClientLog.startup.error("Daemon binary verification failed: \(verifyError, privacy: .private)")
            phase = .fatalError(message: verifyError)
            stepStatuses[.enableDaemon] = .failed(verifyError)
            stepStatuses[.connectAndWatch] = .skipped
            return
        }

        // Step 2: Register daemon with launchd.
        let daemonOK = await runStep(.enableDaemon) {
            await self.daemonManager.enableDaemon()
            if case .error(let msg) = self.daemonManager.state {
                throw StartupError.stepFailed(msg)
            }
        }

        guard !isCancellationRequested else { return }
        guard daemonOK else {
            stepStatuses[.connectAndWatch] = .skipped
            return
        }

        // Step 3: Connect gRPC and start watching setup status.
        let connectOK = await runStep(.connectAndWatch) {
            try await self.connectAndWatchDaemon()
        }

        guard !isCancellationRequested else { return }
        guard connectOK else { return }
        phase = .completed
    }

    /// Connects normally before trying one force re-registration recovery.
    ///
    /// Recovery must only happen after the full initial timeout. Xcode
    /// replacement can leave a registered daemon process unreachable, while
    /// recovering earlier can repeatedly kill a daemon that is still starting.
    private func connectAndWatchDaemon() async throws {
        let client = try onClientsNeeded()
        try checkCancellation()
        daemonManager.connectAndWatch(client: client)

        for _ in 0..<StartupConstants.daemonPollMaxAttempts {
            try checkCancellation()
            if daemonManager.state.isRunning { break }
            if daemonManager.setupPhase == .failed {
                throw StartupError.stepFailed(daemonFailureMessage)
            }
            try await Task.sleep(for: StartupConstants.daemonPollInterval)
        }

        try checkCancellation()
        if daemonManager.state.isRunning { return }

        ClientLog.startup.warning(
            "Daemon unreachable after \(Int(StartupConstants.daemonPollTimeout.components.seconds))s, attempting force re-register recovery"
        )
        await daemonManager.forceReregisterDaemon()
        try checkCancellation()

        if case .error = daemonManager.state {
            throw StartupError.stepFailed("Force re-register failed")
        }

        daemonManager.connectAndWatch(client: client)

        for _ in 0..<StartupConstants.daemonPollMaxAttempts {
            try checkCancellation()
            if daemonManager.state.isRunning { break }
            if daemonManager.setupPhase == .failed {
                throw StartupError.stepFailed(daemonFailureMessage)
            }
            try await Task.sleep(for: StartupConstants.daemonPollInterval)
        }

        try checkCancellation()
        if !daemonManager.state.isRunning {
            let totalSeconds = Int(StartupConstants.daemonPollTimeout.components.seconds) * 2
            // Where it got stuck is the whole question — "unreachable" on its own says only
            // that the poll ran out, and files every distinct cause under one heading.
            throw StartupError.stepFailed(
                """
                Daemon unreachable after force re-register recovery (\(totalSeconds)s total, \
                state \(daemonManager.state.label), setup \(daemonManager.setupPhase))
                """)
        }
    }

    /// Retry the startup sequence after a failure.
    ///
    /// - Parameter allowingAdministratorPrompt: `true` only when the retry is
    ///   itself an explicit administrator-approval action.
    @available(macOS 15.0, *)
    public func retry(allowingAdministratorPrompt: Bool = false) async {
        if daemonManager.setupPhase == .failed {
            await daemonManager.forceReregisterDaemon()
        }
        await start(allowingAdministratorPrompt: allowingAdministratorPrompt)
    }

    /// Human-readable cause of a daemon `FAILED` setup phase, for the retryable
    /// failure UI. `setupMessage` already carries the daemon's `error` detail.
    private var daemonFailureMessage: String {
        let reason = daemonManager.setupMessage
        return reason.isEmpty ? "Daemon reported a fatal setup failure" : reason
    }

    private var isCancellationRequested: Bool {
        isTerminating || Task.isCancelled
    }

    private func checkCancellation() throws {
        if isTerminating {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    // MARK: - Step Runner

    @discardableResult
    private func runStep(
        _ step: StartupStep,
        body: @MainActor () async throws -> Void
    ) async -> Bool {
        guard !isCancellationRequested else { return false }

        stepStatuses[step] = .running
        phase = .running(step: step)

        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval(
            "Startup Step", id: signpostID, "\(step.label, privacy: .public)")
        defer { Self.signposter.endInterval("Startup Step", state) }
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            try checkCancellation()
            try await body()
            try checkCancellation()
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            ClientLog.startup.info(
                "\(step.label, privacy: .public) completed in \(elapsedMs, privacy: .public)ms")
            stepStatuses[step] = .completed
            return true
        } catch HelperInstallError.approvalRequired {
            stepStatuses[step] = .pending
            phase = .requiresAdministratorApproval
            return false
        } catch {
            if isCancellationRequested || error is CancellationError {
                ClientLog.startup.info("\(step.label, privacy: .public) canceled")
                stepStatuses[step] = .pending
                phase = .idle
                return false
            }

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let message = error.localizedDescription
            ClientLog.startup.error(
                "\(step.label, privacy: .public) failed after \(elapsedMs, privacy: .public)ms: \(message, privacy: .private)"
            )
            // Declining the administrator prompt is a decision, not a fault: the step still
            // fails and the message says how to retry, but there is nothing to diagnose.
            if error as? HelperInstallError != .userCanceled {
                ClientDiagnostics.capture(error, tags: ["startup_step": step.label])
            }
            stepStatuses[step] = .failed(message)
            phase = .failed(step: step, message: message)
            return false
        }
    }
}
