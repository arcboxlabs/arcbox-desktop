import RunnerAgentClient

/// The local Agent operations consumed by `RunnerAgentViewModel`.
///
/// Keeping this boundary narrower than the concrete gRPC client makes the
/// long-running watch and image-preparation workflows independently testable.
protocol RunnerAgentControlServicing: Sendable {
    func fetchAgentInfo() async throws -> RunnerAgentInfo
    func getStatus() async throws -> RunnerAgentStatus
    func watchSnapshots() -> AsyncThrowingStream<RunnerAgentSnapshot, Error>
    func drain() async throws
    func resume() async throws
    func unenroll() async throws
    func prepareImages(
        _ kinds: [RunnerImageKind]
    ) -> AsyncThrowingStream<RunnerImagePreparationEvent, Error>
    func getSettings() async throws -> RunnerAgentSettings
    func updateSettings(_ update: RunnerSettingsUpdate) async throws -> RunnerAgentSettings
}

extension RunnerAgentClient: RunnerAgentControlServicing {
    func fetchAgentInfo() async throws -> RunnerAgentInfo {
        try await getAgentInfo()
    }
}
