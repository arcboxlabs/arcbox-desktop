import Foundation

extension ArcBoxClient {
    /// Opens a single `StatsService.Watch` connection and yields machine
    /// stats samples until the stream ends or errors.
    ///
    /// This keeps the gRPC streaming detail (and the `GRPCCore` dependency)
    /// inside the client library — the app layer consumes a plain
    /// `AsyncStream` and owns the reconnect loop, mirroring how
    /// `DaemonManager` drives `WatchSetupStatus`. Cancelling the consuming
    /// task (or dropping the stream) cancels the underlying RPC.
    public func machineStatsStream() -> AsyncStream<Arcbox_V1_MachineStats> {
        let statsService = stats
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await statsService.watch(Arcbox_V1_StatsWatchRequest()) { response in
                        for try await message in response.messages {
                            continuation.yield(message)
                        }
                    }
                } catch {
                    ClientLog.daemon.warning(
                        "WatchStats stream error: \(error.localizedDescription, privacy: .private)")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
