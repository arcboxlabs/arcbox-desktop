import SwiftUI
import DockerClient

/// Detail tab for networks
enum NetworkDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case containers = "Containers"

    var id: String { rawValue }
}

/// Sort field for networks
enum NetworkSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
}

/// Network list state
@Observable
class NetworksViewModel {
    var networks: [NetworkViewModel] = []
    var selectedID: String? = nil
    var activeTab: NetworkDetailTab = .info
    var listWidth: CGFloat = 320
    var showNewNetworkSheet: Bool = false
    var sortBy: NetworkSortField = .name
    var sortAscending: Bool = true

    var networkCount: Int { networks.count }

    var sortedNetworks: [NetworkViewModel] {
        networks.sorted { a, b in
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

    var selectedNetwork: NetworkViewModel? {
        guard let id = selectedID else { return nil }
        return networks.first { $0.id == id }
    }

    func selectNetwork(_ id: String) {
        selectedID = id
    }

    // MARK: - Docker API Operations

    /// Load networks from Docker Engine API.
    func loadNetworks(docker: DockerClient?) async {
        guard let docker else {
            print("[NetworksVM] No docker client available")
            return
        }

        do {
            let response = try await docker.api.NetworkList(.init())
            let networkList = try response.ok.body.json
            networks = networkList.compactMap(NetworkViewModel.init(fromDocker:))
            print("[NetworksVM] Loaded \(networks.count) networks")
        } catch {
            print("[NetworksVM] Error loading networks: \(error)")
        }
    }

    func removeNetwork(_ id: String, docker: DockerClient?) async {
        guard let docker else { return }
        if selectedID == id { selectedID = nil }
        do {
            let response = try await docker.api.NetworkDelete(path: .init(id: id))
            _ = try response.noContent
            print("[NetworksVM] Successfully removed network \(id)")
        } catch {
            print("[NetworksVM] Error removing network \(id): \(error)")
        }
        await loadNetworks(docker: docker)
    }

    func loadSampleData() {
        networks = SampleData.networks
    }
}

// MARK: - Docker API → UI Model Conversion

extension NetworkViewModel {
    /// Create a NetworkViewModel from a Docker Engine API Network.
    init?(fromDocker network: Components.Schemas.Network) {
        guard let id = network.Id, let name = network.Name else { return nil }

        let createdAt: Date
        if let created = network.Created {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdAt = formatter.date(from: created) ?? Date()
        } else {
            createdAt = Date()
        }

        self.init(
            id: id,
            name: name,
            driver: network.Driver ?? "unknown",
            scope: network.Scope ?? "local",
            createdAt: createdAt,
            internal: network.Internal ?? false,
            attachable: network.Attachable ?? false,
            containerCount: 0
        )
    }
}
