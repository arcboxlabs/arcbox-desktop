import ArcBoxClient
import SwiftUI

struct RuntimeStorageDetails: View {
    @Environment(DaemonManager.self) private var daemon

    var body: some View {
        Section("Runtime Storage") {
            if let health = daemon.storageHealth {
                if !daemon.storageHealthIsCurrent {
                    Label("Current storage health is unknown. Showing the last observation.", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(health.volumes.enumerated()), id: \.offset) { _, volume in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(volume.role.label, value: volume.state.label)
                        if !volume.detail.isEmpty {
                            Text(volume.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                if let observedAt = health.observedAt {
                    LabeledContent("Last observed", value: observedAt.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                }
                Text("A read-write mount does not confirm that data can be saved successfully.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Storage health is unknown. The runtime has not supplied a storage observation.")
                    .foregroundStyle(.secondary)
            }

            if daemon.storageWriteFailureMessage != nil {
                Label(
                    "Storage writes are unavailable. Export diagnostics before recovery.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            DiagnosticExportButton()
        }
    }
}
