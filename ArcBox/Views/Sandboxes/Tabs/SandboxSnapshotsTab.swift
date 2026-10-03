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
    @State private var snapshotToDelete: SandboxSnapshotViewModel?
    @State private var snapshotToPromote: SandboxSnapshotViewModel?
    @State private var templateName = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(
            id: SnapshotLoadID(
                sandboxID: sandbox.id,
                client: client.map(ObjectIdentifier.init)
            )
        ) {
            await vm.loadSnapshots(for: sandbox.id, client: client)
        }
        .errorToast(message: Bindable(vm).snapshotsRefreshError)
        .confirmationDialog(
            "Delete Snapshot",
            isPresented: Binding(
                get: { snapshotToDelete != nil },
                set: { if !$0 { snapshotToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let snapshot = snapshotToDelete {
                Button("Delete \"\(snapshot.displayName)\"", role: .destructive) {
                    delete(snapshot)
                    snapshotToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                snapshotToDelete = nil
            }
        } message: {
            Text("This snapshot and its on-disk data will be permanently removed.")
        }
        .alert(
            "Promote to Template",
            isPresented: Binding(
                get: { snapshotToPromote != nil },
                set: { if !$0 { snapshotToPromote = nil } }
            ),
            presenting: snapshotToPromote
        ) { snapshot in
            TextField("Template name", text: $templateName)
            Button("Promote") {
                promote(snapshot)
                snapshotToPromote = nil
            }
            .disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {
                snapshotToPromote = nil
            }
        } message: { _ in
            Text(
                """
                Registers this snapshot as a catalog template. No build runs — the snapshot \
                becomes the template's warm image, so sandboxes created from it restore \
                instead of booting. It stays an unpublished draft until you publish a version.
                """
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Snapshot name", text: $snapshotName, prompt: Text("warm-boot"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Button("Checkpoint", action: checkpoint)
                .disabled(
                    isWorking || vm.isLoadingSnapshots || client == nil
                        || !sandbox.state.isAcceptingCommands
                )
                .help(
                    sandbox.state.isAcceptingCommands
                        ? "Pause, snapshot, and resume this sandbox"
                        : "Sandbox must be ready to checkpoint")

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
            .disabled(isWorking || client == nil || vm.isLoadingSnapshots)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.snapshotsSandboxID != sandbox.id {
            loadingPlaceholder("Preparing snapshots…")
        } else {
            switch vm.snapshotsLoadState {
            case .waiting:
                loadingPlaceholder("Waiting for ArcBox daemon…")
            case .loading:
                loadingPlaceholder("Loading snapshots…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t Load Snapshots", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry", action: refresh)
                        .disabled(client == nil)
                }
            case .loaded:
                loadedContent
            }
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if vm.snapshots.isEmpty {
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

    private func loadingPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func snapshotRow(_ snapshot: SandboxSnapshotViewModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "camera")
                .foregroundStyle(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.system(size: 13))
                Text("\(String(snapshot.id.prefix(12)))  ·  \(snapshot.createdAgo)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Restore") {
                restore(snapshot)
            }
            .disabled(isWorking || vm.isLoadingSnapshots || client == nil)
            .help("Create a new sandbox from this snapshot")

            Button {
                templateName = snapshot.displayName
                snapshotToPromote = snapshot
            } label: {
                Image(systemName: "shippingbox")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isWorking || vm.isLoadingSnapshots || client == nil)
            .help("Promote to a reusable catalog template")

            Button {
                snapshotToDelete = snapshot
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isWorking || vm.isLoadingSnapshots || client == nil)
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

    private func promote(_ snapshot: SandboxSnapshotViewModel) {
        let name = templateName.trimmingCharacters(in: .whitespaces)
        isWorking = true
        Task {
            await vm.promoteSnapshotToTemplate(
                snapshotID: snapshot.id,
                name: name,
                client: client
            )
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

private struct SnapshotLoadID: Equatable {
    let sandboxID: String
    let client: ObjectIdentifier?
}
