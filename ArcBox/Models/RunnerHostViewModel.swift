import FleetControlClient
import Foundation

enum RunnerPoolOS: Equatable {
    case macOS
    case linux

    func matches(_ value: String) -> Bool {
        switch (self, value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
        case (.macOS, "darwin"), (.macOS, "macos"), (.linux, "linux"):
            true
        default:
            false
        }
    }
}

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

    func capabilities(for pool: RunnerPoolOS) -> [FleetCapability] {
        capabilities.filter { pool.matches($0.os) }
    }

    func activeJobCount(for pool: RunnerPoolOS) -> Int {
        inFlightJobs.count { pool.matches($0.os) }
    }
}
