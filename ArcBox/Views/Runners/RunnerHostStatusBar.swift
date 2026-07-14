import FleetControlClient
import SwiftUI

/// Persistent host header showing live Fleet Agent status, capabilities, telemetry, and controls.
struct RunnerHostStatusBar: View {
    let host: RunnerHostViewModel
    let isPerformingAction: Bool
    var onSetDraining: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(color: host.status.color, label: host.status.label)
                Spacer()
                Button(
                    host.isDraining ? "Resume" : "Drain",
                    systemImage: host.isDraining ? "play.fill" : "pause.fill",
                    action: toggleDrainState
                )
                .controlSize(.small)
                .disabled(isPerformingAction || !host.status.canChangeDrainState)
                .help(
                    host.isDraining
                        ? "Resume accepting new jobs"
                        : "Finish running jobs but accept no new ones"
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(host.machineID ?? "Machine ID pending")
                    .font(.caption.monospaced())
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(agentDescription)
                    .font(.caption2)
                    .foregroundStyle(AppColors.textMuted)
            }

            if !host.capabilities.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(host.capabilities) { capability in
                            Label(
                                "\(capability.os)/\(capability.arch) · \(capability.backend.label)",
                                systemImage: capability.backend.systemImage
                            )
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(AppColors.surfaceElevated, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let telemetry = host.telemetry {
                HStack(spacing: 12) {
                    Label("\(telemetry.cpuCount) cores", systemImage: "cpu")
                    Label(
                        "\(telemetry.memoryAvailableMib.formatted()) MiB free",
                        systemImage: "memorychip"
                    )
                    Text("Load \(telemetry.loadAverage1Minute, format: .number.precision(.fractionLength(2)))")
                }
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(10)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
        .padding(8)
    }

    private var agentDescription: String {
        if let agentVersion = host.agentVersion {
            "\(host.chip) · Agent \(agentVersion)"
        } else {
            host.chip
        }
    }

    private func toggleDrainState() {
        onSetDraining(!host.isDraining)
    }
}

extension FleetBackend {
    fileprivate var label: String {
        switch self {
        case .hostRunner: "Host"
        case .docker: "Docker"
        case .vm: "VM"
        case .unspecified, .unrecognized: "Unknown"
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .hostRunner: "desktopcomputer"
        case .docker: "shippingbox"
        case .vm: "macwindow"
        case .unspecified, .unrecognized: "questionmark.circle"
        }
    }
}
