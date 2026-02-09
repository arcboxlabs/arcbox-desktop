import SwiftUI

/// Detail panel tab for containers
enum ContainerDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case logs = "Logs"
    case terminal = "Terminal"
    case files = "Files"

    var id: String { rawValue }
}

/// Container list state, selection, tabs, grouping
@Observable
class ContainersViewModel {
    var containers: [ContainerViewModel] = []
    var selectedID: String? = nil
    var activeTab: ContainerDetailTab = .info
    var expandedGroups: Set<String> = []
    var listWidth: CGFloat = 340
    var searchText: String = ""
    var showNewContainerSheet: Bool = false

    var runningCount: Int {
        containers.filter(\.isRunning).count
    }

    var selectedContainer: ContainerViewModel? {
        guard let id = selectedID else { return nil }
        return containers.first { $0.id == id }
    }

    /// Group containers by compose project
    var composeGroups: [(project: String, containers: [ContainerViewModel])] {
        var groups: [String: [ContainerViewModel]] = [:]
        for container in containers {
            if let project = container.composeProject {
                groups[project, default: []].append(container)
            }
        }
        return groups.sorted { $0.key < $1.key }.map { (project: $0.key, containers: $0.value) }
    }

    /// Containers without a compose project
    var standaloneContainers: [ContainerViewModel] {
        containers.filter { $0.composeProject == nil }
    }

    func selectContainer(_ id: String) {
        selectedID = id
    }

    func toggleGroup(_ group: String) {
        if expandedGroups.contains(group) {
            expandedGroups.remove(group)
        } else {
            expandedGroups.insert(group)
        }
    }

    func isGroupExpanded(_ group: String) -> Bool {
        expandedGroups.contains(group)
    }

    // Mock actions
    func startContainer(_ id: String) {}
    func stopContainer(_ id: String) {}
    func removeContainer(_ id: String) {}

    /// Load sample data
    func loadSampleData() {
        containers = SampleData.containers
        // Expand all compose groups by default
        for container in containers {
            if let project = container.composeProject {
                expandedGroups.insert(project)
            }
        }
    }
}
