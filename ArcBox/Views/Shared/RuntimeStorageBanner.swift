import ArcBoxClient
import SwiftUI

struct RuntimeStorageBanner: View {
    let onDetails: () -> Void
    @Environment(DaemonManager.self) private var daemon

    var body: some View {
        if let recovery = daemon.storageRecovery, !recovery.phase.isTerminal {
            banner(title: "Runtime storage recovery", message: recovery.phase.label)
        } else if let recovery = daemon.storageRecovery, recovery.storageProtected {
            banner(
                title: "Runtime storage remains protected",
                message: recovery.phase == .complete
                    ? "Storage checks completed. Use Recover Read-Write to verify writes and resume workloads."
                    : "Recovery did not complete. Review the diagnostics before trying again.")
        } else if let health = daemon.storageHealth, !health.affectedVolumes.isEmpty,
            daemon.setupPhase.isDockerReady || !daemon.storageHealthIsCurrent
        {
            banner(
                title: "Runtime storage needs attention",
                message: daemon.storageHealthIsCurrent
                    ? "Storage writes are unavailable. Existing workloads may also be affected."
                    : "The last storage observation reported a failure. Current storage health is unknown.")
        }
    }

    private func banner(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.callout)
            }
            Spacer(minLength: 8)
            Button("Storage & Recovery", action: onDetails)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1))
        .accessibilityElement(children: .contain)
    }
}
