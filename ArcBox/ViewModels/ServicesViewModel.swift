import SwiftUI

/// Detail tab for services
enum ServiceDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"

    var id: String { rawValue }
}

/// Service list state
@Observable
class ServicesViewModel {
    var services: [ServiceViewModel] = []
    var selectedID: String? = nil
    var activeTab: ServiceDetailTab = .info
    var listWidth: CGFloat = 320
    var kubernetesEnabled: Bool = false

    var serviceCount: Int { services.count }

    var selectedService: ServiceViewModel? {
        guard let id = selectedID else { return nil }
        return services.first { $0.id == id }
    }

    func selectService(_ id: String) {
        selectedID = id
    }

    func loadSampleData() {
        services = SampleData.services
    }
}
