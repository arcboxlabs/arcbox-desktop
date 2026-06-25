import Foundation
import OSLog
import ServiceManagement

extension DaemonManager {
    // MARK: - Daemon Lifecycle

    /// Register the daemon with launchd. Does not wait for reachability —
    /// that is handled by ``connectAndWatch(client:)``.
    public func enableDaemon() async {
        // ABXD-22: Prevent concurrent enable operations.  Even though we
        // are @MainActor, the `await` suspension points (unregister/register)
        // allow a second SwiftUI .task call to interleave and start a
        // duplicate enable cycle.
        guard !isEnabling else {
            ClientLog.daemon.info("enableDaemon() already in progress, skipping duplicate call")
            return
        }
        isEnabling = true
        defer { isEnabling = false }

        errorMessage = nil
        state = .starting

        // Ensure data directory exists so the daemon can create sockets and state.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try? FileManager.default.createDirectory(
            atPath: "\(home)/.arcbox/run", withIntermediateDirectories: true)

        // ABXD-54: Signature + entitlements are now verified by the orchestrator
        // via verifyDaemonBinary() before enableDaemon() is called.

        let status = daemonService.status
        ClientLog.daemon.info("SMAppService status: \(String(describing: status), privacy: .public)")

        #if DEBUG
            // In development, ALWAYS force unregister+register.
            //
            // Every Xcode build re-signs the daemon binary via `codesign --force`,
            // which generates a new CDHash even for identical content.  SMAppService
            // stores the CDHash from registration time.  If the daemon exits after a
            // rebuild, launchd validates the (now different) CDHash, gets a mismatch,
            // and refuses to spawn with EX_CONFIG (78).  Force re-register ensures
            // the registered CDHash always matches the current binary.
            //
            // This is safe because enableDaemon() is only called once per app launch
            // (guarded by StartupOrchestrator.isStarting + the `.task` nil check in
            // ArcBoxApp), so the SwiftUI .task re-entrancy concern does not apply.
            ClientLog.daemon.info("DEBUG: force re-registering daemon to sync CDHash")
            do {
                try? await daemonService.unregister()
                try daemonService.register()
                ClientLog.daemon.info("Service registered successfully")
                state = .registered
            } catch {
                ClientLog.daemon.error("Failed to register: \(error.localizedDescription, privacy: .private)")
                errorMessage = error.localizedDescription
                state = .error("Failed to register daemon: \(error.localizedDescription)")
            }
        #else
            // In production, skip the destructive unregister+register cycle if the
            // daemon is already enabled.  This avoids killing a healthy daemon when
            // enableDaemon() is called redundantly (e.g. SwiftUI .task re-entrancy).
            if status == .enabled {
                ClientLog.daemon.info("Daemon already registered, skipping re-register")
                if state != .running {
                    state = .registered
                }
                return
            }

            do {
                // Force re-register to ensure BundleProgram resolves against the current
                // app bundle path.
                try? await daemonService.unregister()
                try daemonService.register()
                ClientLog.daemon.info("Service registered successfully")
                state = .registered
            } catch {
                ClientLog.daemon.error("Failed to register: \(error.localizedDescription, privacy: .private)")
                errorMessage = error.localizedDescription
                state = .error("Failed to register daemon: \(error.localizedDescription)")
            }
        #endif
    }

    /// Force re-register the daemon with launchd, regardless of current status.
    ///
    /// This is a **recovery-only** path for when the daemon is registered but
    /// unreachable — typically after Xcode "Replace" (SIGKILL) prevents the
    /// normal `disableDaemon()` cleanup from running, leaving a stale
    /// registration with no live daemon process behind it.
    ///
    /// ⚠️ REGRESSION GUARD — DO NOT call from `enableDaemon()` or any path
    /// reachable by SwiftUI `.task` re-entrancy.  The `enableDaemon()` "skip
    /// if .enabled" guard exists to prevent a **known bug** where redundant
    /// calls each unregister+register the daemon, killing it before it
    /// finishes initializing.  This method must only be invoked **after** a
    /// full poll timeout has confirmed the daemon is truly unreachable, not
    /// merely slow to start.
    public func forceReregisterDaemon() async {
        ClientLog.daemon.warning("Force re-registering daemon (recovery path)")
        errorMessage = nil
        state = .starting

        do {
            try? await daemonService.unregister()
            try daemonService.register()
            ClientLog.daemon.info("Force re-register completed")
            state = .registered
        } catch {
            ClientLog.daemon.error("Force re-register failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = error.localizedDescription
            state = .error("Force re-register failed: \(error.localizedDescription)")
        }
    }

    /// Unregister the daemon from launchd.
    public func disableDaemon() async {
        stopWatching()
        errorMessage = nil
        state = .stopping

        do {
            try await daemonService.unregister()
        } catch {
            errorMessage = error.localizedDescription
        }

        state = .stopped
    }

}
