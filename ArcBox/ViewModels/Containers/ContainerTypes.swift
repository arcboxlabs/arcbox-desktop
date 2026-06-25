import Foundation

extension Notification.Name {
    /// Posted when Docker resources change (e.g. container deleted) so other sections can refresh.
    static let dockerDataChanged = Notification.Name("dockerDataChanged")
}

/// Detail panel tab for containers
enum ContainerDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case logs = "Logs"
    case terminal = "Terminal"
    case files = "Files"

    var id: String { rawValue }
}

/// Sort field for containers
enum ContainerSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
    case status = "Status"
}

/// Container list loading state
enum ContainerLoadState: Equatable {
    case waiting  // Waiting for docker client
    case loading  // Fetching from Docker API
    case loaded  // Fetch completed (containers may be empty)
    case failed(String)  // Fetch failed with error message
}

struct ContainerCreateOptions {
    let image: String
    let name: String
    let platform: String?
    let command: String
    let entrypoint: String
    let workingDir: String
    let autoRemove: Bool
    let restartPolicy: String
    let privileged: Bool
    let readOnlyRootfs: Bool
    let dockerInit: Bool
}
