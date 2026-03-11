import SwiftUI

/// Detail tab for sandboxes
enum SandboxDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case logs = "Logs"

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

/// Sandbox list state
@Observable
class SandboxesViewModel {
    var sandboxes: [SandboxViewModel] = []
    var selectedID: String? = nil
    var activeTab: SandboxDetailTab = .info
    var pageTab: SandboxPageTab = .monitoring
    var listWidth: CGFloat = 320
    var sortBy: SandboxSortField = .name
    var sortAscending: Bool = true

    // Monitoring metrics
    var concurrentSandboxes: Int = 0
    var startRatePerSecond: Double = 0.0
    var peakConcurrentSandboxes: Int = 1
    var concurrentLimit: Int = 20

    var sandboxCount: Int { sandboxes.count }

    var sortedSandboxes: [SandboxViewModel] {
        sandboxes.sorted { a, b in
            let result: Bool
            switch sortBy {
            case .name:
                result = a.alias.localizedCaseInsensitiveCompare(b.alias) == .orderedAscending
            case .dateCreated:
                result = a.startedAt < b.startedAt
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

    func loadSampleData() {
        sandboxes = SampleData.sandboxes
        concurrentSandboxes = sandboxes.filter { $0.isRunning }.count
    }
}
