import DockerClient
import Foundation
import OSLog
import Observation

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
    var loadState: LoadPhase = .waiting
    var refreshError: String?
    var lastSuccessfulListLoad: ContinuousClock.Instant?
    private let listLoadGate = SingleFlightLoadGate()
    var selectedID: String?
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
            let comparison: ComparisonResult
            switch sortBy {
            case .name:
                comparison = a.name.localizedCaseInsensitiveCompare(b.name)
            case .dateCreated:
                comparison = a.createdAt.compare(b.createdAt)
            }
            if comparison == .orderedSame {
                let idComparison = a.id.localizedCaseInsensitiveCompare(b.id)
                return sortAscending
                    ? idComparison == .orderedAscending
                    : idComparison == .orderedDescending
            }
            return sortAscending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
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

        await listLoadGate.run {
            await self.performLoadNetworks(docker: docker)
        }
    }

    private func performLoadNetworks(docker: DockerClient) async {
        let isRefresh = loadState.beginLoading()
        do {
            let response = try await docker.api.NetworkList(.init())
            let networkList = try response.ok.body.json
            var networks: [NetworkViewModel] = []
            for network in networkList {
                guard let id = network.Id else { continue }
                let response = try await docker.api.NetworkInspect(path: .init(id: id))
                guard let inspectedNetwork = try response.networkForList else { continue }
                if let network = NetworkViewModel(fromDocker: inspectedNetwork) {
                    networks.append(network)
                }
            }
            self.networks = networks
            Log.network.info("Loaded \(self.networks.count, privacy: .public) networks")
            loadState = .loaded
            refreshError = nil
            lastSuccessfulListLoad = ContinuousClock().now
        } catch {
            if loadState.cancelLoading(for: error, retainingLoadedContent: isRefresh) {
                return
            }
            Log.network.error("Error loading networks: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .network, operation: "list")
            refreshError = loadState.fail(
                error.localizedDescription,
                retainingLoadedContent: isRefresh
            )
        }
    }

    func removeNetwork(_ id: String, docker: DockerClient?) async {
        lastError = nil
        guard let network = networks.first(where: { $0.id == id }), !network.isSystem else {
            return
        }
        guard network.canDelete else {
            lastError = "Network is in use and cannot be deleted."
            return
        }
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }
        do {
            let response = try await docker.api.NetworkDelete(path: .init(id: network.id))
            if applyNetworkDeletion(response, id: network.id) {
                Log.network.info("Removed network \(network.id, privacy: .private)")
            }
        } catch {
            Log.network.error(
                "Error removing network \(network.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            ErrorReporting.capture(error, domain: .network, operation: "remove")
            lastError = error.localizedDescription
        }
        await loadNetworks(docker: docker)
    }

    @discardableResult
    func applyNetworkDeletion(_ response: Operations.NetworkDelete.Output, id: String) -> Bool {
        if let message = response.deleteFailureMessage {
            lastError = message
            return false
        }
        if selectedID == id { selectedID = nil }
        return true
    }

    /// Create a bridge network. Returns true on success; the failure message lands in `lastError`.
    func createNetwork(name: String, enableIPv6: Bool, docker: DockerClient?) async -> Bool {
        lastError = nil
        // Validate the input before the dependency: a blank name is the user's to fix either way.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastError = "Network name is required."
            return false
        }

        guard let docker else {
            lastError = "Docker client unavailable."
            return false
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
                Log.network.info("Created network \(trimmedName, privacy: .private)")
                await loadNetworks(docker: docker)
                return true
            case let .badRequest(response):
                lastError = Self.errorMessage(from: response.body)
            case let .forbidden(response):
                lastError = Self.errorMessage(from: response.body)
            case let .notFound(response):
                lastError = Self.errorMessage(from: response.body)
            case let .internalServerError(response):
                lastError = Self.errorMessage(from: response.body)
            case let .undocumented(status, _):
                lastError = "Unexpected response status: \(status)."
            }
        } catch {
            Log.network.error(
                "Error creating network \(trimmedName, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            ErrorReporting.capture(error, domain: .network, operation: "create")
            lastError = error.localizedDescription
        }
        return false
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

extension Operations.NetworkDelete.Output {
    nonisolated var deleteFailureMessage: String? {
        switch self {
        case .noContent:
            nil
        case .forbidden(let response):
            switch response.body {
            case .json(let error): error.message
            case .plainText: "Docker cannot remove this network."
            }
        case .notFound(let response):
            switch response.body {
            case .json(let error): error.message
            case .plainText: "Network not found."
            }
        case .internalServerError(let response):
            switch response.body {
            case .json(let error): error.message
            case .plainText: "Docker failed to remove the network."
            }
        case .undocumented(let statusCode, _):
            "Unexpected response status \(statusCode)."
        }
    }
}

// MARK: - Docker API → UI Model Conversion

extension NetworkViewModel {
    /// Create a NetworkViewModel from a Docker Engine API Network.
    init?(fromDocker network: Components.Schemas.Network) {
        guard let id = network.Id, let name = network.Name else { return nil }

        let createdAt = parseISO8601Date(network.Created)

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

extension Operations.NetworkInspect.Output {
    nonisolated var networkForList: Components.Schemas.Network? {
        get throws {
            switch self {
            case .ok(let response):
                try response.body.json
            case .notFound:
                nil
            case .internalServerError, .undocumented:
                try ok.body.json
            }
        }
    }
}
