import AppKit
import ArcBoxClient
import SwiftUI

struct RuntimeStorageRecoverySection: View {
    @Environment(RuntimeStorageRecoveryModel.self) private var recovery
    @Environment(\.arcboxClient) private var client
    @State private var requestedAction: Arcbox_V1_RecoverStorageRequest.Action = .checkOnly
    @State private var showingConfirmation = false

    var body: some View {
        Section("Storage Recovery") {
            HStack {
                Button("Check Storage…") { confirm(.checkOnly) }
                Button("Recover Read-Write…") { confirm(.recover) }
            }
            .disabled(client == nil || recovery.mayBeRunning || recovery.isResettingDockerData)

            Text(
                "Both actions stop runtime workloads and preserve the runtime disks before checking filesystems. Check Storage leaves the runtime stopped."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let progress = recovery.progress {
                HStack {
                    if recovery.mayBeRunning { ProgressView().controlSize(.small) }
                    Text(progress.statusLabel).font(.headline)
                }
                if progress.storageProtected {
                    Label("Storage writes remain protected.", systemImage: "lock.shield")
                        .foregroundStyle(.orange)
                }
                if !progress.message.isEmpty {
                    Text(progress.message).textSelection(.enabled)
                }
                if !progress.recoveryDirectory.isEmpty {
                    Button("Show Preserved Disks and Diagnostics") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: progress.recoveryDirectory, isDirectory: true)
                        ])
                    }
                }
            } else if recovery.mayBeRunning {
                ProgressView("Starting storage recovery…")
            }

            if let message = recovery.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .alert("Stop runtime workloads?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(requestedAction == .checkOnly ? "Stop and Check" : "Stop and Recover") {
                recovery.start(requestedAction)
            }
            .disabled(client == nil || recovery.mayBeRunning || recovery.isResettingDockerData)
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        if requestedAction == .checkOnly {
            return "ArcBox will stop containers, Kubernetes, and sandboxes, preserve the runtime disks, "
                + "and check the filesystems. The runtime will remain stopped after the check."
        }
        return "ArcBox will stop containers, Kubernetes, and sandboxes and preserve the runtime disks. "
            + "ArcBox will restart only if filesystem checks pass, then verify storage writes and a temporary container. "
            + "Filesystem corruption requires further recovery; ArcBox will not erase or force-repair the disks."
    }

    private func confirm(_ action: Arcbox_V1_RecoverStorageRequest.Action) {
        requestedAction = action
        showingConfirmation = true
    }
}
