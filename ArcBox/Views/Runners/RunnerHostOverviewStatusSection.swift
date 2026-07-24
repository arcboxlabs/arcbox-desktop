import FleetPlatformClient
import SwiftUI

struct RunnerHostOverviewStatusSection: View {
    let host: RunnerHostViewModel
    let machine: FleetMachine?
    let workspace: FleetWorkspace?

    var body: some View {
        VStack(spacing: 0) {
            InfoRow(label: "Status", value: host.status.label)
            InfoRow(label: "Workspace", value: workspace?.name ?? "Unavailable")
            InfoRow(label: "Machine", value: machine?.name ?? "This Mac")
            InfoRow(label: "Agent", value: host.agentVersion ?? "Version unavailable")
            InfoRow(label: "Active jobs", value: host.activeJobCount.formatted())
        }
        .infoSectionStyle()
    }
}
