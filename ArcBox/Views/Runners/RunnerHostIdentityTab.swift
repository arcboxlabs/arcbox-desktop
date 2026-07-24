import FleetControlClient
import FleetPlatformClient
import SwiftUI

struct RunnerHostIdentityTab: View {
    let host: RunnerHostViewModel
    let machine: FleetMachine?
    let workspace: FleetWorkspace?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                machineSection
                enrollmentSection
                credentialSection
            }
            .padding(16)
        }
    }

    private var machineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Machine")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Name", value: machine?.name ?? "This Mac")
                InfoRow(label: "Machine ID", value: host.machineID ?? "Unavailable")
                InfoRow(
                    label: "Architecture",
                    value: machine?.arch ?? host.capabilities.first?.arch ?? "Unavailable"
                )
                InfoRow(label: "Agent version", value: host.agentVersion ?? "Unavailable")
                InfoRow(
                    label: "Tags",
                    value: machine?.tags.isEmpty == false
                        ? machine?.tags.joined(separator: ", ") ?? "None"
                        : "None"
                )
            }
            .infoSectionStyle()
        }
    }

    private var enrollmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enrollment")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Workspace", value: workspace?.name ?? "Unavailable")
                InfoRow(label: "Workspace ID", value: workspace?.id ?? "Unavailable")
                InfoRow(label: "Enrolled", value: dateDescription(machine?.enrolledAt))
                InfoRow(label: "Last seen", value: dateDescription(machine?.lastSeen))
                InfoRow(label: "Platform state", value: machine?.status.displayName ?? "Unavailable")
            }
            .infoSectionStyle()
        }
    }

    private var credentialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credential")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Status", value: credentialStatus)
                InfoRow(label: "Storage", value: "Fleet Agent managed")
                InfoRow(label: "Desktop access", value: "Credential contents unavailable")
            }
            .infoSectionStyle()

            Text(
                "The Fleet credential stays in the local Agent and is never exposed to ArcBox Desktop."
            )
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var credentialStatus: String {
        switch host.status {
        case .credentialRejected: "Rejected"
        case .detached: "Detached"
        case .online, .draining, .attaching, .updating: "Present"
        case .unknown: "Unknown"
        }
    }

    private func dateDescription(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable"
    }
}
