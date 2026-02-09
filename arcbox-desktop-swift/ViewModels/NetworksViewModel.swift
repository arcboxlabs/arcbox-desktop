import SwiftUI

/// Detail tab for networks
enum NetworkDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case containers = "Containers"

    var id: String { rawValue }
}

/// Network list state
@Observable
class NetworksViewModel {
    var networks: [NetworkViewModel] = []
    var selectedID: String? = nil
    var activeTab: NetworkDetailTab = .info
    var listWidth: CGFloat = 380

    var networkCount: Int { networks.count }

    var selectedNetwork: NetworkViewModel? {
        guard let id = selectedID else { return nil }
        return networks.first { $0.id == id }
    }

    func selectNetwork(_ id: String) {
        selectedID = id
    }

    func loadSampleData() {
        networks = SampleData.networks
    }
}
