import SwiftUI

/// Detail tab for pods
enum PodDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case logs = "Logs"
    case terminal = "Terminal"

    var id: String { rawValue }
}

/// Pod list state
@Observable
class PodsViewModel {
    var pods: [PodViewModel] = []
    var selectedID: String? = nil
    var activeTab: PodDetailTab = .info
    var listWidth: CGFloat = 320
    var kubernetesEnabled: Bool = false

    var podCount: Int { pods.count }
    var runningCount: Int { pods.filter(\.isRunning).count }

    var selectedPod: PodViewModel? {
        guard let id = selectedID else { return nil }
        return pods.first { $0.id == id }
    }

    func selectPod(_ id: String) {
        selectedID = id
    }

    func loadSampleData() {
        pods = SampleData.pods
    }
}
