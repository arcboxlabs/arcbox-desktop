import ArcBoxClient
import DockerClient
import SwiftUI
import os

/// Container list state, selection, tabs, grouping
@MainActor
@Observable
class ContainersViewModel {
    struct ContainerDetailSnapshot {
        let domain: String?
        let ipAddress: String?
        let mounts: [ContainerMount]
        let rootfsMountPath: String?
    }

    var containers: [ContainerViewModel] = []
    var loadState: ContainerLoadState = .waiting
    var selectedID: String?
    var activeTab: ContainerDetailTab = .info
    var expandedGroups: Set<String> = []
    var listWidth: CGFloat = 320
    var searchText: String = ""
    var isSearching: Bool = false
    var showNewContainerSheet: Bool = false
    var sortBy: ContainerSortField = .name
    var sortAscending: Bool = true
    var lastError: String?

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

    var detailsByID: [String: ContainerDetailSnapshot] = [:]
    var iconsByImage: [String: String] = [:]

    func sortedContainers(_ list: [ContainerViewModel]) -> [ContainerViewModel] {
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

    func matchesSearch(_ container: ContainerViewModel) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return container.name.lowercased().contains(query)
            || container.image.lowercased().contains(query)
            || (container.composeProject?.lowercased().contains(query) ?? false)
    }

    /// Group containers by compose project
    var composeGroups: [(project: String, containers: [ContainerViewModel])] {
        var groups: [String: [ContainerViewModel]] = [:]
        for container in containers where matchesSearch(container) {
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
        sortedContainers(containers.filter { $0.composeProject == nil && matchesSearch($0) })
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

    func applyExpandedGroups(from list: [ContainerViewModel]) {
        for container in list {
            if let project = container.composeProject {
                expandedGroups.insert(project)
            }
        }
    }

    func setContainerRunningState(_ id: String, isRunning: Bool) {
        updateContainer(id) { container in
            container.state = isRunning ? .running : .stopped
        }
    }

    func setTransitioning(_ id: String, _ value: Bool) {
        updateContainer(id) { container in
            container.isTransitioning = value
        }
    }

    /// IDs currently transitioning, used to preserve state across container reloads
    var transitioningIDs: Set<String> {
        Set(containers.filter(\.isTransitioning).map(\.id))
    }

    func removeContainerLocally(_ id: String) {
        containers.removeAll { $0.id == id }
        detailsByID.removeValue(forKey: id)
        if selectedID == id {
            selectedID = nil
        }
    }

    func setContainerDetails(
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

    func updateContainer(_ id: String, mutate: (inout ContainerViewModel) -> Void) {
        guard let index = containers.firstIndex(where: { $0.id == id }) else { return }
        var snapshot = containers
        mutate(&snapshot[index])
        containers = snapshot
    }

    func containerDetailsCache() -> [String: ContainerDetailSnapshot] {
        Dictionary(
            uniqueKeysWithValues: detailsByID.map { id, details in
                (id, details)
            }
        )
    }

    func applyCachedDetails(
        _ cache: [String: ContainerDetailSnapshot],
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

    func applyCachedIcons(to viewModels: inout [ContainerViewModel]) {
        for i in viewModels.indices {
            viewModels[i].iconURL = iconsByImage[viewModels[i].image]
        }
    }

    /// Fetch icon URLs for all unique image references that are not already cached.
    func fetchIcons(client: ArcBoxClient?) async {
        guard let client else { return }
        let uncached = Set(containers.map(\.image)).subtracting(iconsByImage.keys)
        guard !uncached.isEmpty else { return }

        await withTaskGroup(of: (String, String?, Bool).self) { group in
            for image in uncached {
                group.addTask {
                    do {
                        var request = Arcbox_V1_GetImageIconRequest()
                        request.fqin = image
                        let response = try await client.icons.getImageIcon(
                            request, options: ArcBoxClient.defaultCallOptions)
                        let url = response.url.isEmpty ? nil : response.url
                        // (image, url, succeeded) — cache empty url as "no icon available"
                        return (image, url, true)
                    } catch {
                        Log.container.debug(
                            "Icon fetch failed for \(image, privacy: .private): \(error.localizedDescription, privacy: .private)"
                        )
                        // Mark as failed so we don't cache the negative result
                        return (image, nil, false)
                    }
                }
            }
            for await (image, url, succeeded) in group {
                if let url {
                    iconsByImage[image] = url
                } else if succeeded {
                    // RPC succeeded but no icon available — cache to avoid repeated lookups
                    iconsByImage[image] = ""
                }
                // If RPC failed, leave uncached so next load retries
            }
        }

        var snapshot = containers
        applyCachedIcons(to: &snapshot)
        containers = snapshot
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
