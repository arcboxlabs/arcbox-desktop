import AppKit
import DockerClient
import os

/// Wraps observer tokens so they can live inside an OSAllocatedUnfairLock.
/// Access is serialised by the lock, so @unchecked Sendable is safe.
nonisolated private struct _SleepWakeObserverTokens: @unchecked Sendable {
    var sleep: NSObjectProtocol?
    var wake: NSObjectProtocol?
}

/// Monitors macOS sleep/wake events and pauses/unpauses running containers accordingly.
///
/// When the Mac goes to sleep and the setting is enabled, all running containers
/// are paused to save resources. On wake, they are automatically unpaused.

@MainActor
@Observable
final class SleepWakeManager {
    private let logger = Log.sleep

    /// IDs of containers that were paused by this manager (not manually paused by user).
    @ObservationIgnored private var pausedByUs: Set<String> = []
    /// Observer tokens stored in a lock so deinit (nonisolated) can clean them up.
    @ObservationIgnored private let observers = OSAllocatedUnfairLock(initialState: _SleepWakeObserverTokens())

    /// Docker client reference — set from ArcBoxApp when clients are initialized.
    /// DockerClient is a value type (struct), so `weak` is not applicable.
    @ObservationIgnored var dockerClientRef: DockerClient?

    func start() {
        // Ensure idempotency — avoid duplicate observers on repeated calls
        let alreadyStarted = observers.withLockUnchecked { $0.sleep != nil }
        if alreadyStarted { return }

        let workspace = NSWorkspace.shared.notificationCenter
        let sleepToken = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleSleep()
            }
        }
        let wakeToken = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleWake()
            }
        }
        observers.withLockUnchecked { $0 = _SleepWakeObserverTokens(sleep: sleepToken, wake: wakeToken) }
        logger.info("Sleep/wake monitoring started")
    }

    func stop() {
        let tokens = observers.withLockUnchecked { old -> _SleepWakeObserverTokens in
            let prev = old
            old = _SleepWakeObserverTokens()
            return prev
        }
        let workspace = NSWorkspace.shared.notificationCenter
        if let s = tokens.sleep { workspace.removeObserver(s) }
        if let w = tokens.wake { workspace.removeObserver(w) }
        pausedByUs.removeAll()
        logger.info("Sleep/wake monitoring stopped")
    }

    private func handleSleep() async {
        guard UserDefaults.standard.bool(forKey: "pauseContainersWhileSleeping") else { return }
        guard let docker = dockerClientRef else {
            logger.warning("No Docker client available for sleep pause")
            return
        }

        do {
            let response = try await docker.api.ContainerList(query: .init(all: false))
            let containers = try response.ok.body.json
            var paused: [String] = []
            for container in containers {
                guard let id = container.Id, container.State == "running" else { continue }
                do {
                    _ = try await docker.api.ContainerPause(path: .init(id: id))
                    paused.append(id)
                } catch {
                    logger.error("Failed to pause container \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            pausedByUs = Set(paused)
            logger.info("Paused \(paused.count) containers for sleep")
        } catch {
            logger.error("Failed to list containers for sleep pause: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleWake() async {
        guard !pausedByUs.isEmpty else { return }
        guard let docker = dockerClientRef else {
            logger.warning("No Docker client available for wake unpause")
            return
        }

        var unpaused = 0
        var failed: Set<String> = []
        for id in pausedByUs {
            do {
                _ = try await docker.api.ContainerUnpause(path: .init(id: id))
                unpaused += 1
            } catch {
                failed.insert(id)
                logger.error("Failed to unpause container \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("Unpaused \(unpaused)/\(self.pausedByUs.count) containers after wake")
        // Retain failed IDs so they can be retried on next wake cycle
        pausedByUs = failed
    }

    deinit {
        // Observer tokens are behind OSAllocatedUnfairLock (Sendable),
        // so they can be safely accessed from nonisolated deinit.
        let tokens = observers.withLockUnchecked { old -> _SleepWakeObserverTokens in
            let prev = old
            old = _SleepWakeObserverTokens()
            return prev
        }
        let workspace = NSWorkspace.shared.notificationCenter
        if let s = tokens.sleep { workspace.removeObserver(s) }
        if let w = tokens.wake { workspace.removeObserver(w) }
    }
}
