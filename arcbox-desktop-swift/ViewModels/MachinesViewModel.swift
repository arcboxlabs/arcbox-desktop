import SwiftUI

/// Machine list state
@Observable
class MachinesViewModel {
    var machines: [MachineViewModel] = []
    var selectedID: String? = nil

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
