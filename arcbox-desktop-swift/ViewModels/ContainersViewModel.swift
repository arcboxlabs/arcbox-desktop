import SwiftUI
import ArcBoxClient
import DockerClient

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

/// Container list state, selection, tabs, grouping
@Observable
class ContainersViewModel {
    var containers: [ContainerViewModel] = []
    var selectedID: String? = nil
    var activeTab: ContainerDetailTab = .info
    var expandedGroups: Set<String> = []
    var listWidth: CGFloat = 320
    var searchText: String = ""
    var showNewContainerSheet: Bool = false
    var sortBy: ContainerSortField = .name
    var sortAscending: Bool = true

    var runningCount: Int {
        containers.filter(\.isRunning).count
    }

    var selectedContainer: ContainerViewModel? {
        guard let id = selectedID else { return nil }
        return containers.first { $0.id == id }
    }

    private func sortedContainers(_ list: [ContainerViewModel]) -> [ContainerViewModel] {
        list.sorted { a, b in
            let result: Bool
            switch sortBy {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .dateCreated:
                result = a.createdAt < b.createdAt
            case .status:
                result = a.state.rawValue < b.state.rawValue
            }
            return sortAscending ? result : !result
        }
    }

    /// Group containers by compose project
    var composeGroups: [(project: String, containers: [ContainerViewModel])] {
        var groups: [String: [ContainerViewModel]] = [:]
        for container in containers {
            if let project = container.composeProject {
                groups[project, default: []].append(container)
            }
        }
        return groups.sorted { $0.key < $1.key }.map {
            (project: $0.key, containers: sortedContainers($0.value))
        }
    }

    /// Containers without a compose project
    var standaloneContainers: [ContainerViewModel] {
        sortedContainers(containers.filter { $0.composeProject == nil })
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

    // MARK: - gRPC Operations

    /// Load containers from daemon via gRPC, falling back to sample data.
    func loadContainers(client: ArcBoxClient?) async {
        guard let client else {
            loadSampleData()
            return
        }

        do {
            var request = Arcbox_V1_ListContainersRequest()
            request.all = true
            let response = try await client.containers.list(request)
            let viewModels = response.containers.map { summary in
                ContainerViewModel(from: summary)
            }
            containers = viewModels
            // Expand all compose groups by default
            for container in containers {
                if let project = container.composeProject {
                    expandedGroups.insert(project)
                }
            }
        } catch {
            // Fallback to sample data on error
            loadSampleData()
        }
    }

    func startContainer(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        var request = Arcbox_V1_StartContainerRequest()
        request.id = id
        _ = try? await client.containers.start(request)
        await loadContainers(client: client)
    }

    func stopContainer(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        var request = Arcbox_V1_StopContainerRequest()
        request.id = id
        _ = try? await client.containers.stop(request)
        await loadContainers(client: client)
    }

    func removeContainer(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        var request = Arcbox_V1_RemoveContainerRequest()
        request.id = id
        request.force = true
        _ = try? await client.containers.remove(request)
        await loadContainers(client: client)
    }

    // MARK: - Docker API Operations

    /// Load containers from Docker Engine API.
    func loadContainersFromDocker(docker: DockerClient?) async {
        guard let docker else {
            print("[ContainersVM] No docker client available")
            return
        }

        do {
            let response = try await docker.api.ContainerList(.init(query: .init(all: true)))
            let containerList = try response.ok.body.json
            let viewModels = containerList.map { ContainerViewModel(fromDocker: $0) }
            containers = viewModels
            print("[ContainersVM] Loaded \(containers.count) containers")
            for container in containers {
                if let project = container.composeProject {
                    expandedGroups.insert(project)
                }
            }
        } catch {
            print("[ContainersVM] Error loading containers: \(error)")
        }
    }

    func startContainerDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        _ = try? await docker.api.ContainerStart(path: .init(id: id))
        await loadContainersFromDocker(docker: docker)
    }

    func stopContainerDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        _ = try? await docker.api.ContainerStop(path: .init(id: id))
        await loadContainersFromDocker(docker: docker)
    }

    func removeContainerDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        _ = try? await docker.api.ContainerDelete(path: .init(id: id), query: .init(force: true))
        await loadContainersFromDocker(docker: docker)
    }

    /// Load sample data (fallback when daemon is not available)
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

// MARK: - Proto → UI Model Conversion

extension ContainerViewModel {
    /// Create a ContainerViewModel from a gRPC ContainerSummary.
    init(from summary: Arcbox_V1_ContainerSummary) {
        let name = summary.names.first.map {
            $0.hasPrefix("/") ? String($0.dropFirst()) : $0
        } ?? summary.id.prefix(12).description

        let state: ContainerState = switch summary.state {
        case "running": .running
        case "paused": .paused
        case "restarting": .restarting
        case "dead": .dead
        default: .stopped
        }

        let ports = summary.ports.map { port in
            PortMapping(
                hostPort: UInt16(port.hostPort),
                containerPort: UInt16(port.containerPort),
                protocol: port.protocol
            )
        }

        let composeProject = summary.labels["com.docker.compose.project"]

        self.init(
            id: summary.id,
            name: name,
            image: summary.image,
            state: state,
            ports: ports,
            createdAt: Date(timeIntervalSince1970: TimeInterval(summary.created)),
            composeProject: composeProject,
            labels: summary.labels,
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        )
    }

    /// Create a ContainerViewModel from a Docker Engine API ContainerSummary.
    init(fromDocker summary: Components.Schemas.ContainerSummary) {
        let name = summary.Names?.first.map {
            $0.hasPrefix("/") ? String($0.dropFirst()) : $0
        } ?? summary.Id?.prefix(12).description ?? "unknown"

        let state: ContainerState = switch summary.State?.lowercased() {
        case "running": .running
        case "paused": .paused
        case "restarting": .restarting
        case "dead": .dead
        default: .stopped // created, exited, removing -> stopped
        }

        let ports = (summary.Ports ?? []).compactMap { port -> PortMapping? in
            guard let publicPort = port.PublicPort else { return nil }
            return PortMapping(
                hostPort: UInt16(publicPort),
                containerPort: UInt16(port.PrivatePort),
                protocol: port._Type.rawValue
            )
        }

        let labels = summary.Labels?.additionalProperties ?? [:]
        let composeProject = labels["com.docker.compose.project"]

        self.init(
            id: summary.Id ?? "",
            name: name,
            image: summary.Image ?? "",
            state: state,
            ports: ports,
            createdAt: Date(timeIntervalSince1970: TimeInterval(summary.Created ?? 0)),
            composeProject: composeProject,
            labels: labels,
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        )
    }
}
