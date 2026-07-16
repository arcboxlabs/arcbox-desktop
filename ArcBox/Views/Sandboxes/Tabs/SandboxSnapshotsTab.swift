import ArcBoxClient
import SwiftUI

/// Snapshots tab: checkpoint the sandbox and restore/delete its snapshots.
struct SandboxSnapshotsTab: View {
    let sandbox: SandboxViewModel

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    @State private var snapshotName = ""
    @State private var freshNetwork = false
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(id: sandbox.id) {
            await vm.loadSnapshots(for: sandbox.id, client: client)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Snapshot name", text: $snapshotName, prompt: Text("warm-boot"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Button("Checkpoint", action: checkpoint)
                .disabled(isWorking || client == nil || !sandbox.state.isAcceptingCommands)
                .help(
                    sandbox.state.isAcceptingCommands
                        ? "Pause, snapshot, and resume this sandbox"
                        : "Sandbox must be ready or idle to checkpoint")

            Spacer()

            Toggle("Fresh network on restore", isOn: $freshNetwork)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help(
                    "Assign a new TAP/IP to the restored sandbox. Required to restore while the origin is running; needs Firecracker ≥ 1.12 guest assets."
                )

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        // Only render snapshots the view model has confirmed belong to this
        // sandbox; across a selection change `vm.snapshots` briefly still holds
        // the previous sandbox's rows.
        if vm.snapshotsSandboxID != sandbox.id || vm.snapshots.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "camera")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textMuted)
                Text("No snapshots of this sandbox.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Checkpoint captures a booted sandbox so new ones can restore from it in near-zero time.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.snapshots) { snapshot in
                        snapshotRow(snapshot)
                        Divider()
                    }
                }
            }
        }
    }

    private func snapshotRow(_ snapshot: SandboxSnapshotViewModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "camera")
                .foregroundStyle(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.system(size: 13))
                Text("\(String(snapshot.id.prefix(12)))  ·  \(snapshot.createdAt)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Restore") {
                restore(snapshot)
            }
            .disabled(isWorking || client == nil)
            .help("Create a new sandbox from this snapshot")

            Button {
                delete(snapshot)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isWorking || client == nil)
            .help("Delete snapshot")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func checkpoint() {
        isWorking = true
        Task {
            await vm.checkpointSandbox(
                sandbox.id,
                name: snapshotName.trimmingCharacters(in: .whitespaces),
                client: client
            )
            isWorking = false
        }
    }

    private func restore(_ snapshot: SandboxSnapshotViewModel) {
        isWorking = true
        Task {
            _ = await vm.restoreSnapshot(snapshot.id, freshNetwork: freshNetwork, client: client)
            isWorking = false
        }
    }

    private func delete(_ snapshot: SandboxSnapshotViewModel) {
        isWorking = true
        Task {
            await vm.deleteSnapshot(snapshot.id, client: client)
            isWorking = false
        }
    }

    private func refresh() {
        Task {
            await vm.loadSnapshots(for: sandbox.id, client: client)
        }
    }
}
