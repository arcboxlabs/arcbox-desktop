import ArcBoxClient
import Foundation
import OSLog
import Observation

/// Detail tab for sandboxes
enum SandboxDetailTab: String, @MainActor DetailTab {
    case info = "Info"
    case terminal = "Terminal"
    case files = "Files"
    case ports = "Ports"
    case snapshots = "Snapshots"
    case events = "Events"

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
    /// What boots inside the sandbox, in `CreateSandboxRequest.template` form:
    /// empty for the built-in minimal template, `docker:<ref>` for a local
    /// image, or `name[:version]` for a catalog template.
    var template = ""
    var vcpus: UInt32 = 0
    var memoryMiB: UInt64 = 0
    var cmd: [String] = []
    var env: [String: String] = [:]
    var workingDir = ""
    var user = ""
    var networkMode: Arcbox_Sandbox_V1_NetworkMode = .unspecified
    var ttlSeconds: UInt32 = 0
}

/// Sandbox list state backed by the arcbox.sandbox.v1 gRPC API.
@MainActor
@Observable
class SandboxesViewModel {
    var sandboxes: [SandboxViewModel] = []
    var loadState: LoadPhase = .waiting
    var refreshError: String?
    var lastSuccessfulListLoad: ContinuousClock.Instant?
    let listLoadGate = SingleFlightLoadGate()
    @ObservationIgnored let terminalSession = SandboxTerminalSession()
    var selectedID: String?
    var activeTab: SandboxDetailTab = .info
    var sortBy: SandboxSortField = .name
    var sortAscending: Bool = true

    /// Target machine for sandbox RPCs (`x-machine` header). Sandboxes run
    /// nested inside a machine's guest; the default machine hosts them.
    var activeMachineID: String = "default"

    // Sheet presentation
    var showNewSandboxSheet: Bool = false

    /// User-visible error from the last failed operation.
    var lastError: String?

    /// Snapshots of the currently selected sandbox (Snapshots tab).
    var snapshots: [SandboxSnapshotViewModel] = []

    /// Loading state for snapshots belonging to `snapshotsSandboxID`.
    var snapshotsLoadState: LoadPhase = .waiting
    var snapshotsRefreshError: String?
    var snapshotsLoadToken: UUID?

    /// The sandbox `snapshots` belongs to. Guards the Snapshots tab from
    /// rendering or acting on another sandbox's snapshots across a selection
    /// change or a failed reload.
    var snapshotsSandboxID: String?

    /// Authoritative host listeners, keyed by sandbox ID.
    var exposedPorts: [String: [SandboxExposedPort]] = [:]

    /// Loading state for mappings belonging to `exposedPortsSandboxID`.
    var exposedPortsLoadState: LoadPhase = .waiting
    var exposedPortsRefreshError: String?
    var exposedPortsLoadToken: UUID?

    /// The sandbox whose mappings are currently visible in the Ports tab.
    var exposedPortsSandboxID: String?

    /// The template catalog, one entry per version. Fleet-wide, not per
    /// sandbox: loaded on demand by the create sheet and the Snapshots tab.
    var templates: [SandboxTemplateViewModel] = []
    var templatesLoadState: LoadPhase = .waiting
    var templatesRefreshError: String?

    /// Catalog entries a Create request can actually address.
    ///
    /// A bare name resolves to the newest published version and falls back to
    /// the draft only when nothing is published, so a draft shadowed by a
    /// published version has no reference that reaches it. Offering one would
    /// silently create from the published version instead.
    var addressableTemplates: [SandboxTemplateViewModel] {
        let published = Set(templates.lazy.filter { !$0.isDraft }.map(\.name))
        return templates.filter { !$0.isDraft || !published.contains($0.name) }
    }

    var sandboxCount: Int { sandboxes.count }

    var sortedSandboxes: [SandboxViewModel] {
        sandboxes.sorted { a, b in
            let comparison: ComparisonResult
            switch sortBy {
            case .name:
                comparison = a.displayName.localizedCaseInsensitiveCompare(b.displayName)
            case .dateCreated:
                comparison =
                    (a.createdAt ?? .distantPast)
                    .compare(b.createdAt ?? .distantPast)
            }
            if comparison == .orderedSame {
                return sortAscending ? a.id < b.id : a.id > b.id
            }
            return sortAscending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    var selectedSandbox: SandboxViewModel? {
        guard let id = selectedID else { return nil }
        return sandboxes.first { $0.id == id }
    }

    var isLoadingSnapshots: Bool {
        snapshotsLoadToken != nil
    }

    var isLoadingExposedPorts: Bool {
        exposedPortsLoadToken != nil
    }

    func selectSandbox(_ id: String) {
        if selectedID != id {
            snapshotsLoadToken = nil
            exposedPortsLoadToken = nil
        }
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
        if exposedPortsSandboxID == id {
            exposedPortsSandboxID = nil
            exposedPortsLoadToken = nil
            exposedPortsLoadState = .waiting
            exposedPortsRefreshError = nil
        }
        if selectedID == id {
            selectedID = nil
            snapshotsLoadToken = nil
        }
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
