import SwiftUI
import ArcBoxClient
import DockerClient

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

/// Container list state, selection, tabs, grouping
@MainActor
@Observable
class ContainersViewModel {
    private struct ContainerDetailSnapshot {
        let domain: String?
        let ipAddress: String?
        let mounts: [ContainerMount]
        let rootfsMountPath: String?
    }

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
        guard var container = containers.first(where: { $0.id == id }) else { return nil }
        if let details = detailsByID[id] {
            container.domain = details.domain
            container.ipAddress = details.ipAddress
            container.mounts = details.mounts
            container.rootfsMountPath = details.rootfsMountPath
        }
        return container
    }

    private var detailsByID: [String: ContainerDetailSnapshot] = [:]

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

    func selectContainer(_ id: String, docker: DockerClient?) async {
        selectedID = id
        await loadContainerDetailsFromDocker(id, docker: docker)
    }

    func selectContainer(_ id: String, client: ArcBoxClient?, docker: DockerClient?) async {
        selectedID = id
        if docker != nil {
            await loadContainerDetailsFromDocker(id, docker: docker)
        } else {
            await loadContainerDetails(id, client: client)
        }
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
        updateContainer(id) { container in
            container.state = isRunning ? .running : .stopped
        }
    }

    private func setTransitioning(_ id: String, _ value: Bool) {
        updateContainer(id) { container in
            container.isTransitioning = value
        }
    }

    /// IDs currently transitioning, used to preserve state across container reloads
    private var transitioningIDs: Set<String> {
        Set(containers.filter(\.isTransitioning).map(\.id))
    }

    private func removeContainerLocally(_ id: String) {
        containers.removeAll { $0.id == id }
        detailsByID.removeValue(forKey: id)
        if selectedID == id {
            selectedID = nil
        }
    }

    private func setContainerDetails(
        _ id: String,
        domain: String?,
        ipAddress: String?,
        mounts: [ContainerMount],
        rootfsMountPath: String? = nil
    ) {
        let currentContainer = containers.first(where: { $0.id == id })
        let labels = currentContainer?.labels ?? [:]
        let inferredRootfsMountPath = ContainerViewModel.inferRootFSMountPath(
            explicitPath: rootfsMountPath ?? currentContainer?.rootfsMountPath,
            labels: labels,
            mounts: mounts
        )

        detailsByID[id] = ContainerDetailSnapshot(
            domain: domain,
            ipAddress: ipAddress,
            mounts: mounts,
            rootfsMountPath: inferredRootfsMountPath
        )
        updateContainer(id) { container in
            container.domain = domain
            container.ipAddress = ipAddress
            container.mounts = mounts
            container.rootfsMountPath = inferredRootfsMountPath
        }
    }

    private func updateContainer(_ id: String, mutate: (inout ContainerViewModel) -> Void) {
        guard let index = containers.firstIndex(where: { $0.id == id }) else { return }
        var snapshot = containers
        mutate(&snapshot[index])
        containers = snapshot
    }

    private func containerDetailsCache() -> [String: (domain: String?, ipAddress: String?, mounts: [ContainerMount], rootfsMountPath: String?)] {
        Dictionary(
            uniqueKeysWithValues: detailsByID.map { id, details in
                (
                    id,
                    (
                        domain: details.domain,
                        ipAddress: details.ipAddress,
                        mounts: details.mounts,
                        rootfsMountPath: details.rootfsMountPath
                    )
                )
            }
        )
    }

    private func applyCachedDetails(
        _ cache: [String: (domain: String?, ipAddress: String?, mounts: [ContainerMount], rootfsMountPath: String?)],
        to viewModels: inout [ContainerViewModel]
    ) {
        for i in viewModels.indices {
            guard let details = cache[viewModels[i].id] else { continue }
            viewModels[i].domain = details.domain
            viewModels[i].ipAddress = details.ipAddress
            viewModels[i].mounts = details.mounts
            viewModels[i].rootfsMountPath = details.rootfsMountPath
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
        let cachedDetails = containerDetailsCache()
        do {
            var request = Arcbox_V1_ListContainersRequest()
            request.all = true
            let response = try await client.containers.list(request)
            var viewModels = response.containers.map { summary in
                ContainerViewModel(from: summary)
            }
            applyCachedDetails(cachedDetails, to: &viewModels)
            for i in viewModels.indices where currentTransitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            containers = viewModels
            applyExpandedGroups(from: containers)
            if let selectedID, containers.contains(where: { $0.id == selectedID }) {
                await loadContainerDetails(selectedID, client: client)
            }
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

    func loadContainerDetails(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }

        var request = Arcbox_V1_InspectContainerRequest()
        request.id = id

        do {
            let details = try await client.containers.inspect(request)
            setContainerDetails(
                id,
                domain: Self.normalized(details.config.domainname),
                ipAddress: Self.normalized(details.networkSettings.ipAddress),
                mounts: details.mounts.map { mount in
                    ContainerMount(
                        type: mount.type,
                        source: mount.source,
                        destination: mount.destination,
                        isReadOnly: !mount.rw
                    )
                }
            )
        } catch {
            print("[ContainersVM] Error inspecting container \(id): \(error)")
        }
    }

    // MARK: - Docker API Operations

    /// Load containers from Docker Engine API.
    func loadContainersFromDocker(docker: DockerClient?) async {
        guard let docker else {
            print("[ContainersVM] No docker client available")
            return
        }

        let currentTransitioning = transitioningIDs
        let cachedDetails = containerDetailsCache()
        do {
            let response = try await docker.api.ContainerList(.init(query: .init(all: true)))
            let containerList = try response.ok.body.json
            var viewModels = containerList.map { ContainerViewModel(fromDocker: $0) }
            applyCachedDetails(cachedDetails, to: &viewModels)
            // Preserve transitioning state across reload
            for i in viewModels.indices where currentTransitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            containers = viewModels
            print("[ContainersVM] Loaded \(containers.count) containers")
            applyExpandedGroups(from: containers)
            if let selectedID, containers.contains(where: { $0.id == selectedID }) {
                await loadContainerDetailsFromDocker(selectedID, docker: docker)
            }
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
            NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
        } catch {
            print("[ContainersVM] Error removing container \(id): \(error)")
        }
        await loadContainersFromDocker(docker: docker)
    }

    func loadContainerDetailsFromDocker(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }

        do {
            // Prefer raw snapshot to avoid date decoding failures and to support
            // NetworkSettings.Networks.*.IPAddress fallback consistently.
            let snapshot = try await docker.inspectContainerSnapshot(id: id)
            let mounts = snapshot.mounts.compactMap { mount -> ContainerMount? in
                guard let destination = Self.normalized(mount.destination) else { return nil }
                let source = Self.normalized(mount.source) ?? "-"
                return ContainerMount(
                    type: Self.normalized(mount.type) ?? "unknown",
                    source: source,
                    destination: destination,
                    isReadOnly: !(mount.rw ?? true)
                )
            }
            setContainerDetails(
                id,
                domain: Self.normalized(snapshot.domainname),
                ipAddress: Self.normalized(snapshot.ipAddress),
                mounts: mounts,
                rootfsMountPath: Self.normalized(snapshot.rootfsMountPath)
            )
            print(
                "[ContainersVM] Raw inspect snapshot for \(id), domain=\(Self.normalized(snapshot.domainname) ?? "-"), ip=\(Self.normalized(snapshot.ipAddress) ?? "-"), mounts=\(mounts.count), rootfs=\(Self.normalized(snapshot.rootfsMountPath) ?? "-")"
            )
        } catch {
            print("[ContainersVM] Raw inspect snapshot failed for \(id): \(error)")
            do {
                // Fallback to generated inspect model if raw path fails unexpectedly.
                let response = try await docker.api.ContainerInspect(path: .init(id: id))
                let details = try response.ok.body.json

                let mounts = (details.Mounts ?? []).compactMap { mount -> ContainerMount? in
                    guard let destination = Self.normalized(mount.Destination) else { return nil }
                    let source = Self.normalized(mount.Source) ?? "-"
                    return ContainerMount(
                        type: "unknown",
                        source: source,
                        destination: destination,
                        isReadOnly: false
                    )
                }

                setContainerDetails(
                    id,
                    domain: Self.normalized(details.Config?.Domainname),
                    ipAddress: Self.normalized(details.NetworkSettings?.IPAddress),
                    mounts: mounts
                )
                print(
                    "[ContainersVM] Generated inspect fallback for \(id), domain=\(Self.normalized(details.Config?.Domainname) ?? "-"), ip=\(Self.normalized(details.NetworkSettings?.IPAddress) ?? "-"), mounts=\(mounts.count)"
                )
            } catch {
                print("[ContainersVM] Generated inspect fallback failed for \(id): \(error)")
            }
        }
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
        NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
        await loadContainersFromDocker(docker: docker)
    }

    /// Load sample data (fallback when daemon is not available)
    func loadSampleData() {
        containers = SampleData.containers
        detailsByID = [:]
        applyExpandedGroups(from: containers)
    }

    fileprivate static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
        let rootfsMountPath = ContainerViewModel.inferRootFSMountPath(
            explicitPath: nil,
            labels: summary.labels,
            mounts: []
        )

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
            memoryLimitMB: 0,
            rootfsMountPath: rootfsMountPath
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
        let mounts = (summary.Mounts ?? []).compactMap { mount -> ContainerMount? in
            guard let destination = ContainersViewModel.normalized(mount.Destination) else { return nil }
            let source = ContainersViewModel.normalized(mount.Source) ?? "-"
            return ContainerMount(
                type: "unknown",
                source: source,
                destination: destination,
                isReadOnly: false
            )
        }
        let rootfsMountPath = ContainerViewModel.inferRootFSMountPath(
            explicitPath: nil,
            labels: labels,
            mounts: mounts
        )

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
            memoryLimitMB: 0,
            mounts: mounts,
            rootfsMountPath: rootfsMountPath
        )
    }
}
