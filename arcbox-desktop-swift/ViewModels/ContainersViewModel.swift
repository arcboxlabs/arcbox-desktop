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
@MainActor
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

    private func applyExpandedGroups(from list: [ContainerViewModel]) {
        for container in list {
            if let project = container.composeProject {
                expandedGroups.insert(project)
            }
        }
    }

    private func setContainerRunningState(_ id: String, isRunning: Bool) {
        guard let index = containers.firstIndex(where: { $0.id == id }) else { return }
        containers[index].state = isRunning ? .running : .stopped
    }

    private func setTransitioning(_ id: String, _ value: Bool) {
        guard let index = containers.firstIndex(where: { $0.id == id }) else { return }
        containers[index].isTransitioning = value
    }

    /// IDs currently transitioning, used to preserve state across container reloads
    private var transitioningIDs: Set<String> {
        Set(containers.filter(\.isTransitioning).map(\.id))
    }

    private func removeContainerLocally(_ id: String) {
        containers.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = nil
        }
    }

    // MARK: - gRPC Operations

    /// Load containers from daemon via gRPC, falling back to sample data.
    func loadContainers(client: ArcBoxClient?) async {
        guard let client else {
            loadSampleData()
            return
        }

        let currentTransitioning = transitioningIDs
        do {
            var request = Arcbox_V1_ListContainersRequest()
            request.all = true
            let response = try await client.containers.list(request)
            var viewModels = response.containers.map { summary in
                ContainerViewModel(from: summary)
            }
            for i in viewModels.indices where currentTransitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            containers = viewModels
            applyExpandedGroups(from: containers)
        } catch {
            // Fallback to sample data on error
            loadSampleData()
        }
    }

    func startContainer(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        setTransitioning(id, true)
        var request = Arcbox_V1_StartContainerRequest()
        request.id = id
        do {
            _ = try await client.containers.start(request)
            setContainerRunningState(id, isRunning: true)
        } catch {
            print("[ContainersVM] Error starting container \(id): \(error)")
        }
        setTransitioning(id, false)
        await loadContainers(client: client)
    }

    func stopContainer(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        setTransitioning(id, true)
        var request = Arcbox_V1_StopContainerRequest()
        request.id = id
        do {
            _ = try await client.containers.stop(request)
            setContainerRunningState(id, isRunning: false)
        } catch {
            print("[ContainersVM] Error stopping container \(id): \(error)")
        }
        setTransitioning(id, false)
        await loadContainers(client: client)
    }

    func removeContainer(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        var request = Arcbox_V1_RemoveContainerRequest()
        request.id = id
        request.force = true
        do {
            _ = try await client.containers.remove(request)
            removeContainerLocally(id)
        } catch {
            print("[ContainersVM] Error removing container \(id): \(error)")
        }
        await loadContainers(client: client)
    }

    // MARK: - Docker API Operations

    /// Load containers from Docker Engine API.
    func loadContainersFromDocker(docker: DockerClient?) async {
        guard let docker else {
            print("[ContainersVM] No docker client available")
            return
        }

        let currentTransitioning = transitioningIDs
        do {
            let response = try await docker.api.ContainerList(.init(query: .init(all: true)))
            let containerList = try response.ok.body.json
            var viewModels = containerList.map { ContainerViewModel(fromDocker: $0) }
            // Preserve transitioning state across reload
            for i in viewModels.indices where currentTransitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            containers = viewModels
            print("[ContainersVM] Loaded \(containers.count) containers")
            applyExpandedGroups(from: containers)
        } catch {
            print("[ContainersVM] Error loading containers: \(error)")
        }
    }

    func startContainerDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        setTransitioning(id, true)
        do {
            _ = try await docker.api.ContainerStart(path: .init(id: id))
            setContainerRunningState(id, isRunning: true)
        } catch {
            print("[ContainersVM] Error starting container \(id): \(error)")
        }
        setTransitioning(id, false)
        await loadContainersFromDocker(docker: docker)
    }

    func stopContainerDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        setTransitioning(id, true)
        do {
            _ = try await docker.api.ContainerStop(path: .init(id: id))
            setContainerRunningState(id, isRunning: false)
        } catch {
            print("[ContainersVM] Error stopping container \(id): \(error)")
        }
        setTransitioning(id, false)
        await loadContainersFromDocker(docker: docker)
    }

    func removeContainerDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        do {
            _ = try await docker.api.ContainerDelete(path: .init(id: id), query: .init(force: true))
            removeContainerLocally(id)
        } catch {
            print("[ContainersVM] Error removing container \(id): \(error)")
        }
        await loadContainersFromDocker(docker: docker)
    }

    // MARK: - Batch Docker Operations

    func startContainersDocker(_ ids: [String], docker: DockerClient?) async {
        guard let docker else { return }
        let stoppedIDs = ids.filter { id in
            containers.first(where: { $0.id == id })?.isRunning == false
        }
        for id in stoppedIDs { setTransitioning(id, true) }
        await withTaskGroup(of: Void.self) { group in
            for id in stoppedIDs {
                group.addTask { [weak self] in
                    do {
                        _ = try await docker.api.ContainerStart(path: .init(id: id))
                        await self?.setContainerRunningState(id, isRunning: true)
                    } catch {
                        print("[ContainersVM] Error starting container \(id): \(error)")
                    }
                }
            }
        }
        for id in stoppedIDs { setTransitioning(id, false) }
        await loadContainersFromDocker(docker: docker)
    }

    func stopContainersDocker(_ ids: [String], docker: DockerClient?) async {
        guard let docker else { return }
        let runningIDs = ids.filter { id in
            containers.first(where: { $0.id == id })?.isRunning == true
        }
        for id in runningIDs { setTransitioning(id, true) }
        await withTaskGroup(of: Void.self) { group in
            for id in runningIDs {
                group.addTask { [weak self] in
                    do {
                        _ = try await docker.api.ContainerStop(path: .init(id: id))
                        await self?.setContainerRunningState(id, isRunning: false)
                    } catch {
                        print("[ContainersVM] Error stopping container \(id): \(error)")
                    }
                }
            }
        }
        for id in runningIDs { setTransitioning(id, false) }
        await loadContainersFromDocker(docker: docker)
    }

    func removeContainersDocker(_ ids: [String], docker: DockerClient?) async {
        guard let docker else { return }
        for id in ids { setTransitioning(id, true) }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [weak self] in
                    do {
                        _ = try await docker.api.ContainerDelete(path: .init(id: id), query: .init(force: true))
                        await self?.removeContainerLocally(id)
                    } catch {
                        print("[ContainersVM] Error removing container \(id): \(error)")
                    }
                }
            }
        }
        await loadContainersFromDocker(docker: docker)
    }

    /// Load sample data (fallback when daemon is not available)
    func loadSampleData() {
        containers = SampleData.containers
        applyExpandedGroups(from: containers)
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
