import ArcBoxClient
import Foundation
import OSLog

/// Drives the System VM hypervisor backend switch (Settings > System).
///
/// Lives at app scope rather than view scope: `SetSystemVmBackend` restarts
/// the System VM and runs for tens of seconds, so the in-flight state must
/// survive the settings pane being closed or navigated away from — both to
/// keep the outcome observable and to prevent a second switch racing the
/// first.
@MainActor
@Observable
final class SystemVmBackendModel {
    /// The daemon's actual backend; `nil` while unknown (not loaded, unreachable).
    private(set) var currentBackend: SystemVmBackend?
    private(set) var isSwitching = false
    private(set) var lastError: String?

    /// Load the current backend. No-op while a switch is in flight; pass a
    /// `nil` client (e.g. daemon not running) to mark the backend unknown.
    func load(client: ArcBoxClient?) async {
        guard !isSwitching else { return }
        guard let client else {
            currentBackend = nil
            return
        }
        setBackend(await fetch(client: client))
        if currentBackend != nil {
            lastError = nil
        }
    }

    /// Start a backend switch. Returns immediately; progress is observable
    /// via `isSwitching`, `currentBackend`, and `lastError`.
    func beginSwitch(to target: SystemVmBackend, client: ArcBoxClient?) {
        guard !isSwitching, let client else { return }
        isSwitching = true
        lastError = nil
        Task {
            await switchBackend(to: target, client: client)
        }
    }

    private func switchBackend(to target: SystemVmBackend, client: ArcBoxClient) async {
        var request = Arcbox_V1_SetSystemVmBackendRequest()
        request.backend = target.proto
        do {
            let info = try await client.system.setSystemVmBackend(
                request, options: ArcBoxClient.systemVmRestartCallOptions)
            setBackend(SystemVmBackend(proto: info.backend))
        } catch {
            Log.daemon.error(
                "Failed to switch System VM backend: \(error.localizedDescription, privacy: .private)"
            )
            ErrorReporting.capture(error, domain: .daemon, operation: "setSystemVmBackend")
            // A failed switch leaves the previous backend durable daemon-side;
            // re-read so the UI reflects the actual state.
            setBackend(await fetch(client: client))
            lastError = ArcBoxClient.userMessage(for: error)
        }
        isSwitching = false
    }

    /// Publishes the backend and mirrors it into the analytics super
    /// properties, so every event can be segmented by hypervisor.
    private func setBackend(_ backend: SystemVmBackend?) {
        currentBackend = backend
        guard let backend else { return }
        Analytics.register(["system_vm_backend": backend.rawValue])
    }

    private func fetch(client: ArcBoxClient) async -> SystemVmBackend? {
        do {
            let info = try await client.system.getSystemVmBackend(
                .init(), options: ArcBoxClient.defaultCallOptions)
            return SystemVmBackend(proto: info.backend)
        } catch {
            Log.daemon.error(
                "Failed to load System VM backend: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }
}
