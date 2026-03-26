import ArcBoxClient
import Foundation
import GRPCCore
import OSLog

/// Subscribes to sandbox lifecycle events via gRPC server-streaming
/// and posts `.sandboxChanged` notifications for UI refresh.
@MainActor
@Observable
final class SandboxEventMonitor {

    private var task: Task<Void, Never>?
    private var isStopped = true

    private var debounceWorkItem: DispatchWorkItem?
    private static let debounceInterval: TimeInterval = 0.3

    // MARK: - Lifecycle

    func start(client: ArcBoxClient, machineID: String) {
        task?.cancel()
        isStopped = false

        let metadata = SandboxMetadata.forMachine(machineID)

        task = Task {
            var backoffSeconds: UInt64 = 2
            while !Task.isCancelled, !isStopped {
                do {
                    try await client.sandboxes.events(
                        Sandbox_V1_SandboxEventsRequest(),
                        metadata: metadata
                    ) { [weak self] response in
                        for try await _ in response.messages {
                            guard !Task.isCancelled else { break }
                            await MainActor.run {
                                self?.debouncedPost()
                            }
                        }
                    }
                    // Stream ended cleanly — reset backoff.
                    backoffSeconds = 2
                } catch {
                    if Task.isCancelled || isStopped { break }
                    Log.sandbox.warning(
                        "Sandbox event stream error, reconnecting in \(backoffSeconds)s: \(error.localizedDescription, privacy: .public)"
                    )
                }

                if Task.isCancelled || isStopped { break }
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
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    // MARK: - Debounce

    private func debouncedPost() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem {
            NotificationCenter.default.post(name: .sandboxChanged, object: nil)
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.debounceInterval,
            execute: item
        )
    }
}
