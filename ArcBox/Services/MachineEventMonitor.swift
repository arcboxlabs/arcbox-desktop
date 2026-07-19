import ArcBoxClient
import Foundation
import GRPCCore
import OSLog

// Machine notifications come from the arcbox.v1 MachineService event stream,
// distinct from Docker events and the sandbox stream.
extension Notification.Name {
    static let machineChanged = Notification.Name("machineChanged")
}

/// Subscribes to machine lifecycle events via gRPC server-streaming and posts
/// a debounced `.machineChanged` so the Machines list refreshes on create /
/// start / idle / stop / remove without polling. Any event — including the
/// server's `resync` signal after dropped events — triggers a reload, so the
/// exact payload is irrelevant here.
@MainActor
@Observable
final class MachineEventMonitor {
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isStopped = true
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(300)

    func start(client: ArcBoxClient) {
        task?.cancel()
        isStopped = false

        let stoppedCheck = { @MainActor [weak self] in self?.isStopped ?? true }
        task = Task.detached {
            var backoffSeconds: UInt64 = 2
            while !Task.isCancelled {
                if await stoppedCheck() { break }
                do {
                    try await client.machines.events(Arcbox_V1_MachineEventsRequest()) { response in
                        // Refresh on every (re)connect: events that occur while
                        // the stream is down during backoff are not replayed
                        // (the server only sends `resync` for its own drops), so
                        // re-list once the stream re-establishes to catch up.
                        await MainActor.run { [weak self] in
                            self?.debouncedPost()
                        }
                        for try await _ in response.messages {
                            guard !Task.isCancelled else { break }
                            await MainActor.run { [weak self] in
                                self?.debouncedPost()
                            }
                        }
                    }
                    // Stream ended cleanly — reset backoff.
                    backoffSeconds = 2
                } catch {
                    if Task.isCancelled { break }
                    if await stoppedCheck() { break }
                    Log.machine.warning(
                        "Machine event stream error, reconnecting in \(backoffSeconds)s: \(error.localizedDescription, privacy: .private)"
                    )
                }

                if Task.isCancelled { break }
                if await stoppedCheck() { break }
                try? await Task.sleep(for: .seconds(backoffSeconds))
                // Exponential backoff capped at 30 seconds.
                backoffSeconds = min(backoffSeconds * 2, 30)
            }
            Log.machine.info("Machine event monitor stopped")
        }
        Log.machine.info("Machine event monitor started")
    }

    func stop() {
        isStopped = true
        task?.cancel()
        task = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func debouncedPost() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .machineChanged, object: nil)
        }
    }
}
