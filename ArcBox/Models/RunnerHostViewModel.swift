import FleetControlClient

/// Presentation model for this Mac, derived entirely from Fleet Agent state.
struct RunnerHostViewModel: Identifiable, Equatable {
    let machineID: String?
    let status: RunnerHostStatus
    let capabilities: [FleetCapability]
    let inFlightJobs: [FleetInFlightJob]
    let telemetry: FleetHostTelemetry?
    let agentVersion: String?
    let chip: String
    let isDraining: Bool

    init(snapshot: FleetAgentSnapshot, agentInfo: FleetAgentInfo?) {
        machineID = snapshot.machineID
        status = RunnerHostStatus(snapshot: snapshot)
        capabilities = snapshot.capabilities
        inFlightJobs = snapshot.inFlightJobs
        telemetry = snapshot.telemetry
        agentVersion = agentInfo?.agentVersion
        chip = RunnerHostCapability.chipName
        isDraining = snapshot.isDraining
    }

    var id: String {
        machineID ?? "local-fleet-agent"
    }

    var activeJobCount: Int {
        inFlightJobs.count
    }
}
