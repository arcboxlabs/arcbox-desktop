import SwiftUI

/// Detail tab options for machines (matches container pattern)
enum MachineDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case logs = "Logs"
    case terminal = "Terminal"
    case files = "Files"

    var id: String { rawValue }
}

/// Machine list state
@Observable
class MachinesViewModel {
    var machines: [MachineViewModel] = []
    var selectedID: String? = nil
    var activeTab: MachineDetailTab = .info
    var searchText: String = ""
    var isSearching: Bool = false

    var filteredMachines: [MachineViewModel] {
        guard !searchText.isEmpty else { return machines }
        return machines.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.distro.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedMachine: MachineViewModel? {
        guard let selectedID else { return nil }
        return machines.first { $0.id == selectedID }
    }

    var runningCount: Int {
        machines.filter(\.isRunning).count
    }

    var totalCount: Int { machines.count }

    func selectMachine(_ id: String) {
        selectedID = id
    }

    // Mock actions
    func startMachine(_ id: String) {}
    func stopMachine(_ id: String) {}
    func deleteMachine(_ id: String) {}

    func loadSampleData() {
        machines = SampleData.machines
    }
}
