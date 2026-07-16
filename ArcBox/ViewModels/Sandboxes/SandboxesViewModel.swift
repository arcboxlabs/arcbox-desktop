import ArcBoxClient
import OSLog
import SwiftUI

/// Detail tab for sandboxes
enum SandboxDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case terminal = "Terminal"
    case files = "Files"
    case ports = "Ports"
    case snapshots = "Snapshots"
    case events = "Events"

    var id: String { rawValue }
}

/// Top-level tab for sandboxes page
enum SandboxPageTab: String, CaseIterable, Identifiable {
    case list = "List"
    case monitoring = "Monitoring"

    var id: String { rawValue }
}

/// Sort field for sandboxes
enum SandboxSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
}

/// Parameters for creating a sandbox.
struct SandboxCreateSpec {
    var labels: [String: String] = [:]
    /// Docker image reference; resolved to its overlay2 layer directory and
    /// passed as `rootfs` (mirrors `abctl sandbox create --from-image`).
    var image = ""
    /// Direct rootfs path; ignored when `image` is set. Empty = daemon default.
    var rootfs = ""
    var kernel = ""
    var bootArgs = ""
    var vcpus: UInt32 = 0
    var memoryMiB: UInt64 = 0
    var cmd: [String] = []
    var env: [String: String] = [:]
    var workingDir = ""
    var user = ""
    var networkMode = ""
    var ttlSeconds: UInt32 = 0
}

/// Sandbox list state backed by the sandbox.v1 gRPC API.
@MainActor
@Observable
class SandboxesViewModel {
    var sandboxes: [SandboxViewModel] = []
    var selectedID: String?
    var activeTab: SandboxDetailTab = .info
    var pageTab: SandboxPageTab = .list
    var listWidth: CGFloat = 320
    var sortBy: SandboxSortField = .name
    var sortAscending: Bool = true

    /// Target machine for sandbox RPCs (`x-machine` header). Sandboxes run
    /// nested inside a machine's guest; the default machine hosts them.
    var activeMachineID: String = "default"

    // Monitoring metrics
    var concurrentSandboxes: Int = 0
    var startRatePerSecond: Double = 0.0
    var peakConcurrentSandboxes: Int = 0
    var concurrentLimit: Int = 20

    // Sheet presentation
    var showNewSandboxSheet: Bool = false

    /// User-visible error from the last failed operation.
    var lastError: String?

    /// Snapshots of the currently selected sandbox (Snapshots tab).
    var snapshots: [SandboxSnapshotViewModel] = []

    /// The sandbox `snapshots` belongs to. Guards the Snapshots tab from
    /// rendering or acting on another sandbox's snapshots across a selection
    /// change or a failed reload.
    var snapshotsSandboxID: String?

    /// Ports exposed from this app session, keyed by sandbox ID.
    var exposedPorts: [String: [SandboxExposedPort]] = [:]

    @ObservationIgnored private var createTimestamps: [Date] = []

    var sandboxCount: Int { sandboxes.count }

    var sortedSandboxes: [SandboxViewModel] {
        sandboxes.sorted { a, b in
            let result: Bool
            switch sortBy {
            case .name:
                result =
                    a.displayName.localizedCaseInsensitiveCompare(b.displayName)
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

    func clearError() {
        lastError = nil
    }

    // MARK: - Shared helpers (used by the gRPC extensions)

    func updateSandbox(_ id: String, mutate: (inout SandboxViewModel) -> Void) {
        guard let index = sandboxes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sandboxes[index])
    }

    func setTransitioning(_ id: String, _ value: Bool) {
        updateSandbox(id) { $0.isTransitioning = value }
    }

    var transitioningIDs: Set<String> {
        Set(sandboxes.filter(\.isTransitioning).map(\.id))
    }

    func removeSandboxLocally(_ id: String) {
        sandboxes.removeAll { $0.id == id }
        exposedPorts[id] = nil
        if selectedID == id {
            selectedID = nil
        }
        updateMonitoringMetrics()
    }

    func updateMonitoringMetrics() {
        concurrentSandboxes = sandboxes.count { $0.state.isActive }
        if concurrentSandboxes > peakConcurrentSandboxes {
            peakConcurrentSandboxes = concurrentSandboxes
        }
    }

    /// Record a sandbox start event and recompute the 5-second rolling start rate.
    func recordSandboxStart() {
        let now = Date()
        createTimestamps.append(now)
        let windowStart = now.addingTimeInterval(-5)
        createTimestamps.removeAll { $0 < windowStart }
        startRatePerSecond = Double(createTimestamps.count) / 5.0
    }

    /// Log, report, and surface an error; returns the user-facing message.
    @discardableResult
    func reportError(_ error: Error, operation: String, surface: Bool = true) -> String {
        Log.sandbox.error(
            "Sandbox \(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
        )
        ErrorReporting.capture(error, domain: .sandbox, operation: operation)
        let message = ArcBoxClient.userMessage(for: error)
        if surface {
            lastError = message
        }
        return message
    }
}
