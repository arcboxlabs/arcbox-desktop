import ArcBoxClient
import Foundation
import GRPCCore
import OSLog

// Sandbox notifications are separate from Docker events: they originate from
// the ArcBox gRPC event stream, not the Docker daemon.
extension Notification.Name {
    static let sandboxChanged = Notification.Name("sandboxChanged")
}

/// Subscribes to sandbox lifecycle events via gRPC server-streaming, posts
/// `.sandboxChanged` notifications for list refresh, and keeps a bounded
/// in-memory feed of recent events for the per-sandbox Events tab.
@MainActor
@Observable
final class SandboxEventMonitor {
    /// Most recent events, oldest first. Bounded to `maxRecentEvents`.
    private(set) var recentEvents: [SandboxEventRecord] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isStopped = true

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(300)
    private static let maxRecentEvents = 500

    // MARK: - Lifecycle

    func start(client: ArcBoxClient, machineID: String) {
        task?.cancel()
        isStopped = false

        let metadata = SandboxMetadata.forMachine(machineID)

        let stoppedCheck = { @MainActor [weak self] in self?.isStopped ?? true }
        task = Task.detached {
            var backoffSeconds: UInt64 = 2
            while !Task.isCancelled {
                if await stoppedCheck() { break }
                do {
                    try await client.sandboxes.events(
                        Sandbox_V1_SandboxEventsRequest(),
                        metadata: metadata
                    ) { response in
                        for try await event in response.messages {
                            guard !Task.isCancelled else { break }
                            await MainActor.run { [weak self] in
                                self?.record(event)
                            }
                        }
                    }
                    // Stream ended cleanly — reset backoff.
                    backoffSeconds = 2
                } catch {
                    if Task.isCancelled { break }
                    if await stoppedCheck() { break }
                    Log.sandbox.warning(
                        "Sandbox event stream error, reconnecting in \(backoffSeconds)s: \(error.localizedDescription, privacy: .private)"
                    )
                }

                if Task.isCancelled { break }
                if await stoppedCheck() { break }
                try? await Task.sleep(for: .seconds(backoffSeconds))
                // Exponential backoff capped at 30 seconds.
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
            Log.sandbox.info("Sandbox event monitor stopped")
        }
        Log.sandbox.info("Sandbox event monitor started")
    }

    func stop() {
        isStopped = true
        task?.cancel()
        task = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Events for one sandbox, newest first.
    func events(for sandboxID: String) -> [SandboxEventRecord] {
        recentEvents.filter { $0.sandboxID == sandboxID }.reversed()
    }

    // MARK: - Private

    private func record(_ event: Sandbox_V1_SandboxEvent) {
        recentEvents.append(SandboxEventRecord(from: event))
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - Self.maxRecentEvents)
        }
        debouncedPost()
    }

    private func debouncedPost() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .sandboxChanged, object: nil)
        }
    }
}
