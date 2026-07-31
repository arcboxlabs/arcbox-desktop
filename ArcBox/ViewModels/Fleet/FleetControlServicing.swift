import FleetControlClient

/// The local Agent operations consumed by `FleetViewModel`.
///
/// Keeping this boundary narrower than the concrete gRPC client makes the
/// long-running watch and image-preparation workflows independently testable.
protocol FleetControlServicing: Sendable {
    func fetchAgentInfo() async throws -> FleetAgentInfo
    func getStatus() async throws -> FleetAgentStatus
    func watchSnapshots() -> AsyncThrowingStream<FleetAgentSnapshot, Error>
    func drain() async throws
    func resume() async throws
    func unenroll() async throws
    func prepareImages(
        _ kinds: [FleetImageKind]
    ) -> AsyncThrowingStream<FleetImagePreparationEvent, Error>
    func getSettings() async throws -> FleetAgentSettings
    func updateSettings(_ update: FleetSettingsUpdate) async throws -> FleetAgentSettings
}

extension FleetControlClient: FleetControlServicing {
    func fetchAgentInfo() async throws -> FleetAgentInfo {
        try await getAgentInfo()
    }
}
