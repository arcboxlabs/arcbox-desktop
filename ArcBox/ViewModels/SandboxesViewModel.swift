import ArcBoxClient
import OSLog
import SwiftUI

/// Detail tab for sandboxes
enum SandboxDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case terminal = "Terminal"

    var id: String { rawValue }
}

/// Top-level tab for sandboxes page
enum SandboxPageTab: String, CaseIterable, Identifiable {
    case monitoring = "Monitoring"
    case list = "List"

    var id: String { rawValue }
}

/// Sort field for sandboxes
enum SandboxSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
}

/// Sandbox list state with gRPC integration.
@MainActor
@Observable
class SandboxesViewModel {
    var sandboxes: [SandboxViewModel] = []
    var selectedID: String? = nil
    var activeTab: SandboxDetailTab = .info
    var pageTab: SandboxPageTab = .monitoring
    var listWidth: CGFloat = 320
    var sortBy: SandboxSortField = .name
    var sortAscending: Bool = true

    /// Target machine for sandbox RPCs (x-machine header).
    var activeMachineID: String = "default"

    // Monitoring metrics
    var concurrentSandboxes: Int = 0
    var startRatePerSecond: Double = 0.0
    var peakConcurrentSandboxes: Int = 0
    var concurrentLimit: Int = 20

    // User-visible error from last failed operation
    var errorMessage: String? = nil

    @ObservationIgnored private var createTimestamps: [Date] = []

    // Snapshot list
    var snapshots: [Sandbox_V1_SnapshotSummary] = []

    var sandboxCount: Int { sandboxes.count }

    var sortedSandboxes: [SandboxViewModel] {
        sandboxes.sorted { a, b in
            let result: Bool
            switch sortBy {
            case .name:
                result = a.displayName.localizedCaseInsensitiveCompare(b.displayName)
                    == .orderedAscending
            case .dateCreated:
                result = (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
            }
            return sortAscending ? result : !result
        }
    }

    var selectedSandbox: SandboxViewModel? {
        guard let id = selectedID else { return nil }
        return sandboxes.first { $0.id == id }
    }

    func selectSandbox(_ id: String) {
        selectedID = id
    }

    // MARK: - gRPC Operations

    func loadSandboxes(client: ArcBoxClient?) async {
        guard let client else { return }
        let transitioning = transitioningIDs
        let existingByID = Dictionary(uniqueKeysWithValues: sandboxes.map { ($0.id, $0) })
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        do {
            let response = try await client.sandboxes.list(
                Sandbox_V1_ListSandboxesRequest(),
                metadata: metadata
            )
            var viewModels = response.sandboxes.map { summary -> SandboxViewModel in
                var vm = SandboxViewModel(from: summary)
                // Preserve detail fields loaded by a prior inspect call so the list
                // refresh does not wipe data the summary endpoint does not return.
                if let existing = existingByID[vm.id] {
                    vm.preserveDetailFrom(existing)
                }
                return vm
            }
            for i in viewModels.indices where transitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            sandboxes = viewModels
            updateMonitoringMetrics()
        } catch {
            Log.sandbox.error(
                "Error loading sandboxes: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadSandboxDetails(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_InspectSandboxRequest()
        request.id = id
        do {
            let info = try await client.sandboxes.inspect(request, metadata: metadata)
            updateSandbox(id) { sandbox in
                sandbox.applyDetails(from: info)
            }
        } catch {
            Log.sandbox.error(
                "Error inspecting sandbox \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func createSandbox(
        id: String = "",
        labels: [String: String] = [:],
        vcpus: UInt32 = 0,
        memoryMiB: UInt64 = 0,
        ttlSeconds: UInt32 = 0,
        client: ArcBoxClient?
    ) async -> String? {
        guard let client else { return nil }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_CreateSandboxRequest()
        request.id = id
        request.labels = labels
        if vcpus > 0 || memoryMiB > 0 {
            request.limits.vcpus = vcpus
            request.limits.memoryMib = memoryMiB
        }
        request.ttlSeconds = ttlSeconds
        do {
            let response = try await client.sandboxes.create(request, metadata: metadata)
            Log.sandbox.info("Created sandbox \(response.id, privacy: .public)")
            recordSandboxStart()
            await loadSandboxes(client: client)
            return response.id
        } catch {
            Log.sandbox.error(
                "Error creating sandbox: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func stopSandbox(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        setTransitioning(id, true)
        var request = Sandbox_V1_StopSandboxRequest()
        request.id = id
        do {
            _ = try await client.sandboxes.stop(request, metadata: metadata)
            // Set intermediate state; event monitor will deliver the final .stopped transition.
            updateSandbox(id) { $0.state = .stopping }
        } catch {
            Log.sandbox.error(
                "Error stopping sandbox \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
        setTransitioning(id, false)
    }

    func removeSandbox(_ id: String, force: Bool = false, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        setTransitioning(id, true)
        var request = Sandbox_V1_RemoveSandboxRequest()
        request.id = id
        request.force = force
        do {
            _ = try await client.sandboxes.remove(request, metadata: metadata)
            removeSandboxLocally(id)
        } catch {
            Log.sandbox.error(
                "Error removing sandbox \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
            setTransitioning(id, false)
        }
    }

    // MARK: - Snapshot Operations

    func loadSnapshots(client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        do {
            let response = try await client.snapshots.listSnapshots(
                Sandbox_V1_ListSnapshotsRequest(),
                metadata: metadata
            )
            snapshots = response.snapshots
        } catch {
            Log.sandbox.error(
                "Error loading snapshots: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteSnapshot(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Sandbox_V1_DeleteSnapshotRequest()
        request.snapshotID = id
        do {
            _ = try await client.snapshots.deleteSnapshot(request, metadata: metadata)
            snapshots.removeAll { $0.id == id }
        } catch {
            Log.sandbox.error(
                "Error deleting snapshot \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Private Helpers

    private var transitioningIDs: Set<String> {
        Set(sandboxes.filter(\.isTransitioning).map(\.id))
    }

    private func updateSandbox(_ id: String, mutate: (inout SandboxViewModel) -> Void) {
        guard let index = sandboxes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sandboxes[index])
    }

    private func setTransitioning(_ id: String, _ value: Bool) {
        updateSandbox(id) { $0.isTransitioning = value }
    }

    private func removeSandboxLocally(_ id: String) {
        sandboxes.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = nil
        }
        updateMonitoringMetrics()
    }

    private func updateMonitoringMetrics() {
        let active = sandboxes.filter { $0.state.isActive }
        concurrentSandboxes = active.count
        if concurrentSandboxes > peakConcurrentSandboxes {
            peakConcurrentSandboxes = concurrentSandboxes
        }
    }

    /// Record a sandbox start event and recompute the 5-second rolling start rate.
    private func recordSandboxStart() {
        let now = Date()
        createTimestamps.append(now)
        let windowStart = now.addingTimeInterval(-5)
        createTimestamps.removeAll { $0 < windowStart }
        startRatePerSecond = Double(createTimestamps.count) / 5.0
    }

    func clearError() {
        errorMessage = nil
    }
}
