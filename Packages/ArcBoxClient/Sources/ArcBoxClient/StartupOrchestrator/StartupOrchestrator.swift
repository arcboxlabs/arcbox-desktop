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
    /// A step the user has to unblock in System Settings. It fails like any other and the
    /// message says what to do, but there is nothing here to diagnose, so it is not
    /// reported.
    case requiresUserAction(String)

    var errorDescription: String? {
        switch self {
        case .stepFailed(let msg), .requiresUserAction(let msg): return msg
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
    public var isRuntimeReady: Bool { isReady && daemonManager.isDockerReady }

    /// Current daemon-provided setup detail for progress UI.
    public var setupMessage: String { daemonManager.runtimeProgressMessage }

    /// Retryable runtime failure reported after the gRPC connection succeeds: the daemon
    /// gave up, or it is up but its System runtime failed.
    public var runtimeFailureMessage: String? {
        guard isReady else { return nil }
        if case .error(let message) = daemonManager.state { return message }
        if case .failed(let reason) = daemonManager.systemRuntimeIssue {
            return reason.isEmpty ? "The Docker runtime failed to start." : reason
        }
        return nil
    }

    /// Whether a retry is possible.
    public var canRetry: Bool {
        if case .failed = phase { return true }
        return runtimeFailureMessage != nil
    }

    // Dependencies
    /// The daemon this startup drives; views read runtime detail (emulation, downloads,
    /// the System runtime issue) from it.
    public let daemonManager: DaemonManager
    private let onClientsNeeded: @MainActor () throws -> ArcBoxClient
    private let hostSupportsVirtualization: @MainActor () -> Bool

    private static let signposter = OSSignposter(
        subsystem: "com.arcboxlabs.desktop", category: "startup")

    /// Owns the active run so app termination can cancel retries as well as
    /// the initial startup task.
    private var startupTask: Task<Void, Never>?
    private var isTerminating = false

    public init(
        daemonManager: DaemonManager,
        onClientsNeeded: @escaping @MainActor () throws -> ArcBoxClient,
        hostSupportsVirtualization: @escaping @MainActor () -> Bool = { HostVirtualization.isAvailable }
    ) {
        self.daemonManager = daemonManager
        self.onClientsNeeded = onClientsNeeded
        self.hostSupportsVirtualization = hostSupportsVirtualization

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
        await run(allowingAdministratorPrompt: allowingAdministratorPrompt, restartingFailedDaemon: false)
    }

    @available(macOS 15.0, *)
    private func run(allowingAdministratorPrompt: Bool, restartingFailedDaemon: Bool) async {
        guard !isTerminating else { return }
        if let startupTask {
            await startupTask.value
            return
        }

        let task = Task {
            // The restart runs in the startup task, so a second Retry waits for it instead
            // of stopping the daemon again, and quitting waits for the daemon to be back.
            if restartingFailedDaemon, !isCancellationRequested, retryRestartsDaemon {
                await daemonManager.forceReregisterDaemon()
            }
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

        // Without hardware virtualization the daemon can never boot its VM: launchd
        // restarts it in a crash loop, and the helper install asks for an administrator
        // password for nothing. It is a property of the Mac, so it is not reported.
        guard hostSupportsVirtualization() else {
            ClientLog.startup.error("Hardware virtualization is unavailable; not starting the daemon")
            phase = .virtualizationUnavailable
            return
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
                throw self.daemonManager.daemonService.status == .requiresApproval
                    ? StartupError.requiresUserAction(msg)
                    : StartupError.stepFailed(msg)
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
        await run(allowingAdministratorPrompt: allowingAdministratorPrompt, restartingFailedDaemon: true)
    }

    /// Whether `retry()` restarts the daemon: it gave up, or its System startup failed,
    /// which waits for a storage recovery before it tries again. Ask `retryWarning()` first.
    private var retryRestartsDaemon: Bool {
        daemonManager.setupPhase == .failed || systemStartupFailed
    }

    /// Read through the host phase: a restart resets the phase but leaves the last
    /// `systemRuntime` in place until the new daemon reports.
    private var systemStartupFailed: Bool {
        daemonManager.setupPhase.isHostReady && daemonManager.systemRuntime == .failed
    }

    /// The confirmation `retry()` needs because it restarts the daemon; `nil` when it does
    /// not.
    ///
    /// Retrying a failed System startup restarts a daemon that still hosts Machines and
    /// macOS guests, and the daemon stops all of them when it exits. No sandbox runs then:
    /// they live on the System VM. A daemon in `FAILED` is exiting anyway.
    public func retryWarning() async -> String? {
        guard systemStartupFailed else { return nil }
        // An unknown list is not an empty one: the restart stops them all the same.
        let listed = try? await onClientsNeeded().machines.list(
            .with { $0.all = true }, options: ArcBoxClient.defaultCallOptions)
        return Self.restartWarning(listing: listed?.machines ?? [])
    }

    /// Names the Linux Machines a daemon restart stops: every one that runs or boots,
    /// except `default`, the System VM the retry is for. States are the daemon's wire
    /// strings. macOS guests stop too, but this client cannot list them.
    static func restartWarning(listing machines: [Arcbox_V1_MachineSummary]) -> String {
        let names = machines.filter { $0.id != "default" && ["running", "starting"].contains($0.state) }.map(\.name)
        guard !names.isEmpty else {
            return "Retrying restarts the ArcBox daemon, which stops any running machines and macOS virtual machines."
        }
        let running = names.count == 1 ? "the running machine" : "the running machines"
        return "Retrying restarts the ArcBox daemon, which stops \(running) \(names.formatted(.list(type: .and))), "
            + "as well as any running macOS virtual machines."
    }

    /// Human-readable cause of a daemon `FAILED` setup phase, for the retryable
    /// failure UI. `setupMessage` already carries the daemon's `error` detail.
    /// Outcomes the user chose or must undo themselves — declining the administrator
    /// prompt, or switching ArcBox off in Login Items. They fail the step and say what to
    /// do; reporting them only fills the tracker with settings.
    private static func isUpToTheUser(_ error: any Error) -> Bool {
        if case StartupError.requiresUserAction = error { return true }
        return error as? HelperInstallError == .userCanceled
    }

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
            if !Self.isUpToTheUser(error) {
                ClientDiagnostics.capture(error, tags: ["startup_step": step.label])
            }
            stepStatuses[step] = .failed(message)
            phase = .failed(step: step, message: message)
            return false
        }
    }
}
