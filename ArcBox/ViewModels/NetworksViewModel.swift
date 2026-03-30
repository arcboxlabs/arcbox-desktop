import SwiftUI
import DockerClient
import OSLog

/// Sort field for networks
enum NetworkSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
}

/// Network list state
@MainActor
@Observable
class NetworksViewModel {
    var networks: [NetworkViewModel] = []
    var selectedID: String? = nil
    var listWidth: CGFloat = 320
    var showNewNetworkSheet: Bool = false
    var searchText: String = ""
    var isSearching: Bool = false
    var sortBy: NetworkSortField = .name
    var sortAscending: Bool = true
    var lastError: String?

    var networkCount: Int { networks.count }

    var sortedNetworks: [NetworkViewModel] {
        let filtered: [NetworkViewModel]
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = networks.filter {
                $0.name.lowercased().contains(query)
                    || $0.driver.lowercased().contains(query)
            }
        } else {
            filtered = networks
        }

        return filtered.sorted { a, b in
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
            Log.network.debug("No docker client available")
            return
        }

        do {
            let response = try await docker.api.NetworkList(.init())
            let networkList = try response.ok.body.json
            networks = networkList.compactMap(NetworkViewModel.init(fromDocker:))
            Log.network.info("Loaded \(self.networks.count, privacy: .public) networks")
        } catch {
            Log.network.error("Error loading networks: \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeNetwork(_ id: String, docker: DockerClient?) async {
        lastError = nil
        guard let docker else { return }
        if selectedID == id { selectedID = nil }
        do {
            let response = try await docker.api.NetworkDelete(path: .init(id: id))
            _ = try response.noContent
            Log.network.info("Removed network \(id, privacy: .public)")
        } catch {
            Log.network.error("Error removing network \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        await loadNetworks(docker: docker)
    }

    func createNetwork(name: String, enableIPv6: Bool, docker: DockerClient?) async -> String? {
        guard let docker else {
            return "Docker client unavailable."
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Network name is required."
        }

        let payload = Operations.NetworkCreate.Input.Body.jsonPayload(
            Name: trimmedName,
            Driver: "bridge",
            EnableIPv6: enableIPv6
        )

        do {
            let output = try await docker.api.NetworkCreate(body: .json(payload))
            switch output {
            case .created:
                Log.network.info("Created network \(trimmedName, privacy: .public)")
                await loadNetworks(docker: docker)
                return nil
            case let .badRequest(response):
                return Self.errorMessage(from: response.body)
            case let .forbidden(response):
                return Self.errorMessage(from: response.body)
            case let .notFound(response):
                return Self.errorMessage(from: response.body)
            case let .internalServerError(response):
                return Self.errorMessage(from: response.body)
            case let .undocumented(status, _):
                return "Unexpected response status: \(status)."
            }
        } catch {
            Log.network.error("Error creating network \(trimmedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private static func errorMessage<T>(from body: T) -> String where T: Sendable {
        switch body {
        case let value as Operations.NetworkCreate.Output.BadRequest.Body:
            return (try? value.json.message) ?? "Invalid request."
        case let value as Operations.NetworkCreate.Output.Forbidden.Body:
            return (try? value.json.message) ?? "Operation forbidden."
        case let value as Operations.NetworkCreate.Output.NotFound.Body:
            return (try? value.json.message) ?? "Resource not found."
        case let value as Operations.NetworkCreate.Output.InternalServerError.Body:
            return (try? value.json.message) ?? "Server error."
        default:
            return "Failed to create network."
        }
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
            if let parsed = formatter.date(from: created) {
                createdAt = parsed
            } else {
                // Retry without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                createdAt = formatter.date(from: created) ?? .distantPast
            }
        } else {
            createdAt = .distantPast
        }

        self.init(
            id: id,
            name: name,
            driver: network.Driver ?? "unknown",
            scope: network.Scope ?? "local",
            createdAt: createdAt,
            internal: network.Internal ?? false,
            attachable: network.Attachable ?? false,
            containerCount: network.Containers?.additionalProperties.count ?? 0
        )
    }
}
