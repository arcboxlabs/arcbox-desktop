import ArcBoxClient
import Foundation
import GRPCCore
import GRPCProtobuf
import OSLog
import SwiftProtobuf

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
    /// The effective backend when the subscription started; see ``follow(_:client:machineID:)``.
    @ObservationIgnored private var followedBackend: SystemVmBackend?

    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(300)
    static let maxRecentEvents = 500
    /// A subscription open this long counts as healthy: the longest reconnect wait.
    nonisolated private static let heldSubscription: Duration = .seconds(30)

    // MARK: - Lifecycle

    /// Subscribes while the daemon runs. A backend that cannot run sandboxes rejects the
    /// subscription for good, so after that only a change of effective backend subscribes
    /// again. Pass every daemon update.
    func follow(_ daemon: DaemonManager, client: ArcBoxClient?, machineID: String) {
        guard daemon.state.isRunning, let client else {
            if !isStopped { stop() }
            return
        }
        guard isStopped || daemon.effectiveBackend != followedBackend else { return }
        followedBackend = daemon.effectiveBackend
        start(client: client, machineID: machineID)
    }

    private func start(client: ArcBoxClient, machineID: String) {
        task?.cancel()
        isStopped = false

        let metadata = SandboxMetadata.forMachine(machineID)

        let stoppedCheck = { @MainActor [weak self] in self?.isStopped ?? true }
        task = Task.detached {
            var backoffSeconds: UInt64 = 2
            while !Task.isCancelled {
                if await stoppedCheck() { break }
                do {
                    let (streamError, subscribedFor): ((any Error)?, Duration) = try await client.sandboxes.events(
                        Arcbox_Sandbox_V1_SandboxEventsRequest(),
                        metadata: metadata
                    ) { response in
                        if case .failure(let rejection) = response.accepted {
                            return (rejection, .zero)
                        }
                        let subscribedAt = ContinuousClock.now
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
                            return (error, ContinuousClock.now - subscribedAt)
                        }
                        return (nil, ContinuousClock.now - subscribedAt)
                    }
                    // Only a subscription that held resets the backoff. The daemon
                    // accepts one and ends it at once when the guest runs no
                    // sandboxes; resetting then reconnects and resyncs every 2 s.
                    if subscribedFor >= Self.heldSubscription {
                        backoffSeconds = 2
                    }
                    if let streamError { throw streamError }
                } catch {
                    if Task.isCancelled { break }
                    if await stoppedCheck() { break }
                    if Self.cannotRunSandboxes(error) {
                        Log.sandbox.info(
                            "Not watching sandbox events: \(error.localizedDescription, privacy: .private)"
                        )
                        break
                    }
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

    /// Whether the daemon refused because the effective backend cannot run sandboxes on
    /// this hardware, which no retry changes. Its status, `FAILED_PRECONDITION`, also
    /// covers transient states, so only the `NESTED_VIRT_UNSUPPORTED` detail decides.
    nonisolated private static func cannotRunSandboxes(_ error: any Error) -> Bool {
        guard let error = error as? RPCError, error.code == .failedPrecondition,
            let status = try? error.unpackGoogleRPCStatus()
        else { return false }
        return status.details.contains { detail in
            guard let any = detail.any else { return false }
            return (try? Arcbox_Sandbox_V1_ErrorInfo(unpackingAny: any))?.code == .nestedVirtUnsupported
        }
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
