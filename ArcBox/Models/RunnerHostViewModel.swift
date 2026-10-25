import RunnerAgentClient

/// Presentation model for this Mac, derived entirely from Runner Agent state.
struct RunnerHostViewModel: Identifiable, Equatable {
    let hostID: String?
    let status: RunnerHostStatus
    let capabilities: [RunnerCapability]
    let inFlightJobs: [RunnerInFlightJob]
    let telemetry: RunnerHostTelemetry?
    let agentVersion: String?
    let chip: String
    let isDraining: Bool

    init(snapshot: RunnerAgentSnapshot, agentInfo: RunnerAgentInfo?) {
        hostID = snapshot.hostID
        status = RunnerHostStatus(snapshot: snapshot)
        capabilities = snapshot.capabilities
        inFlightJobs = snapshot.inFlightJobs
        telemetry = snapshot.telemetry
        agentVersion = agentInfo?.agentVersion
        chip = RunnerHostCapability.chipName
        isDraining = snapshot.isDraining
    }

    var id: String {
        hostID ?? "local-runner-agent"
    }

    var activeJobCount: Int {
        inFlightJobs.count
    }
}
