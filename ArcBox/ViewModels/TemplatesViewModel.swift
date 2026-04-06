import SwiftUI

/// Detail tab for templates
enum TemplateDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case sandboxes = "Sandboxes"

    var id: String { rawValue }
}

/// Sort field for templates
enum TemplateSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
}

/// Template list state
@MainActor
@Observable
class TemplatesViewModel {
    var templates: [TemplateViewModel] = []
    var selectedID: String?
    var activeTab: TemplateDetailTab = .info
    var listWidth: CGFloat = 320
    var sortBy: TemplateSortField = .name
    var sortAscending: Bool = true

    var templateCount: Int { templates.count }

    var sortedTemplates: [TemplateViewModel] {
        templates.sorted { a, b in
            let result: Bool
            switch sortBy {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .dateCreated:
                result = a.createdAt < b.createdAt
            }
            return sortAscending ? result : !result
        }
    }

    var selectedTemplate: TemplateViewModel? {
        guard let id = selectedID else { return nil }
        return templates.first { $0.id == id }
    }

    func selectTemplate(_ id: String) {
        selectedID = id
    }

    func loadSampleData() {
        templates = SampleData.templates
    }
}
