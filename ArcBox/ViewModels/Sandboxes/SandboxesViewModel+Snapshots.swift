import ArcBoxClient
import Foundation
import OSLog

extension SandboxesViewModel {
    // MARK: - Snapshot Operations (SandboxSnapshotService)

    /// Load snapshots taken from one sandbox.
    func loadSnapshots(for sandboxID: String, client: ArcBoxClient?) async {
        guard let client else { return }
        // Drop a previously-selected sandbox's snapshots up front so a slow or
        // failing load never leaves another sandbox's snapshots on screen.
        if snapshotsSandboxID != sandboxID {
            snapshots = []
            snapshotsSandboxID = sandboxID
        }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_ListSnapshotsRequest()
        request.sandboxID = sandboxID
        do {
            let response = try await client.snapshots.listSnapshots(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            snapshots = response.snapshots.map(SandboxSnapshotViewModel.init(from:))
        } catch {
            reportError(error, operation: "list_snapshots", surface: false)
        }
    }

    /// Checkpoint a ready/idle sandbox into a reusable snapshot.
    /// The sandbox is paused, snapshotted, then resumed by the daemon.
    func checkpointSandbox(_ id: String, name: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        setTransitioning(id, true)
        var request = Sandbox_V1_CheckpointRequest()
        request.sandboxID = id
        request.name = name
        do {
            // No per-call timeout: checkpointing pauses the VM and writes
            // vmstate + guest memory to disk, which can exceed the default.
            let response = try await client.snapshots.checkpoint(request, metadata: metadata)
            Log.sandbox.info("Checkpointed \(id, privacy: .public) → \(response.snapshotID, privacy: .public)")
            await loadSnapshots(for: id, client: client)
        } catch {
            reportError(error, operation: "checkpoint")
        }
        setTransitioning(id, false)
    }

    /// Restore a new sandbox from a snapshot. Returns the new sandbox ID.
    ///
    /// `freshNetwork` maps to `network_override`: required to run multiple
    /// restores of one snapshot concurrently, and requires Firecracker ≥ 1.12
    /// guest assets. Without it, restoring while the origin sandbox is still
    /// running fails with FAILED_PRECONDITION (vsock path conflict).
    @discardableResult
    func restoreSnapshot(
        _ snapshotID: String,
        freshNetwork: Bool = false,
        client: ArcBoxClient?
    ) async -> String? {
        guard let client else { return nil }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_RestoreRequest()
        request.snapshotID = snapshotID
        request.networkOverride = freshNetwork
        do {
            let response = try await client.snapshots.restore(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            Log.sandbox.info("Restored \(snapshotID, privacy: .public) → \(response.id, privacy: .public)")
            recordSandboxStart()
            await loadSandboxes(client: client)
            return response.id
        } catch {
            reportError(error, operation: "restore")
            return nil
        }
    }

    /// Delete a snapshot and its on-disk data.
    func deleteSnapshot(_ snapshotID: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_DeleteSnapshotRequest()
        request.snapshotID = snapshotID
        do {
            _ = try await client.snapshots.deleteSnapshot(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            snapshots.removeAll { $0.id == snapshotID }
        } catch {
            reportError(error, operation: "delete_snapshot")
        }
    }
}
