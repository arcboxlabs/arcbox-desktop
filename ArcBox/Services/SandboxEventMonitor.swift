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

    /// Called for every event as it arrives, before the debounced list refresh.
    /// `.sandboxChanged` carries no payload, so consumers that need the event
    /// itself — notifications — take it from here.
    @ObservationIgnored var onEvent: ((SandboxEventRecord) -> Void)?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isStopped = true

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(300)
    static let maxRecentEvents = 500

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
                    let streamError: (any Error)? = try await client.sandboxes.events(
                        Arcbox_Sandbox_V1_SandboxEventsRequest(),
                        metadata: metadata
                    ) { response in
                        // Events have no replay cursor. Resync after every
                        // successful subscription to cover the reconnect gap.
                        await MainActor.run {
                            NotificationCenter.default.post(name: .sandboxChanged, object: nil)
                        }
                        do {
                            for try await frame in response.messages {
                                guard !Task.isCancelled else { break }
                                guard case .event(let event)? = frame.payload else { continue }
                                await MainActor.run { [weak self] in
                                    self?.record(event)
                                }
                            }
                        } catch {
                            return error
                        }
                        return nil
                    }
                    // Reaching the response handler means the subscription
                    // succeeded, even if the stream later disconnected.
                    backoffSeconds = 2
                    if let streamError { throw streamError }
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

    private func record(_ event: Arcbox_Sandbox_V1_SandboxEvent) {
        let record = SandboxEventRecord(from: event)
        recentEvents.append(record)
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - Self.maxRecentEvents)
        }
        onEvent?(record)
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
