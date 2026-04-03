import OSLog
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
@MainActor
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

    // TODO: Implement when machine lifecycle is connected to gRPC
    func startMachine(_ id: String) {
        Log.machine.warning("Not implemented: \(#function) for \(id, privacy: .private)")
    }
    func stopMachine(_ id: String) {
        Log.machine.warning("Not implemented: \(#function) for \(id, privacy: .private)")
    }
    func deleteMachine(_ id: String) {
        Log.machine.warning("Not implemented: \(#function) for \(id, privacy: .private)")
    }

    func loadSampleData() {
        machines = SampleData.machines
    }
}
