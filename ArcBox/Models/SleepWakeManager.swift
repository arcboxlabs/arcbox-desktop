import AppKit
import DockerClient
import OSLog

/// Monitors macOS sleep/wake events and pauses/unpauses running containers accordingly.
///
/// When the Mac goes to sleep and the setting is enabled, all running containers
/// are paused to save resources. On wake, they are automatically unpaused.
@MainActor
@Observable
final class SleepWakeManager {
    private let logger = Logger(subsystem: "com.arcbox.desktop", category: "SleepWakeManager")

    /// IDs of containers that were paused by this manager (not manually paused by user).
    @ObservationIgnored private var pausedByUs: Set<String> = []
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// Weak reference to the Docker client — set from ArcBoxApp when clients are initialized.
    @ObservationIgnored weak var dockerClientRef: DockerClient?

    func start() {
        // Ensure idempotency — avoid duplicate observers on repeated calls
        if sleepObserver != nil { return }

        let workspace = NSWorkspace.shared.notificationCenter
        sleepObserver = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleSleep()
            }
        }
        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleWake()
            }
        }
        logger.info("Sleep/wake monitoring started")
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        if let sleepObserver { workspace.removeObserver(sleepObserver) }
        if let wakeObserver { workspace.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
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
        for id in pausedByUs {
            do {
                _ = try await docker.api.ContainerUnpause(path: .init(id: id))
                unpaused += 1
            } catch {
                logger.error("Failed to unpause container \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("Unpaused \(unpaused)/\(self.pausedByUs.count) containers after wake")
        pausedByUs.removeAll()
    }

    deinit {
        // Observers are removed in stop(), but ensure cleanup
        let workspace = NSWorkspace.shared.notificationCenter
        if let sleepObserver { workspace.removeObserver(sleepObserver) }
        if let wakeObserver { workspace.removeObserver(wakeObserver) }
    }
}
