// Foundation precedes local packages per the repository import-order guideline.
// swift-format-ignore: OrderedImports
import Foundation
import ArcBoxAuth

protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {}

/// Authenticated REST client for the Platform operations needed by Fleet onboarding.
public final class FleetPlatformClient: Sendable {
    private let configuration: FleetPlatformConfiguration
    private let accessTokenProvider: any AccessTokenProviding
    private let http: any HTTPDataLoading

    public init(
        configuration: FleetPlatformConfiguration = .current,
        accessTokenProvider: any AccessTokenProviding,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
        self.http = session
    }

    init(
        configuration: FleetPlatformConfiguration,
        accessTokenProvider: any AccessTokenProviding,
        http: any HTTPDataLoading
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
        self.http = http
    }

    /// List workspaces the current Platform identity belongs to.
    public func listWorkspaces() async throws -> [FleetWorkspace] {
        try await send(path: "v1/workspaces", method: "GET")
    }

    /// Create and return the workspace's one-hour Fleet enrollment token,
    /// invalidating any token previously issued for the workspace.
    public func createEnrollmentToken(workspaceID: String) async throws -> FleetEnrollmentToken {
        try await send(
            path: "v1/fleet/enrollment-token",
            method: "POST",
            workspaceID: workspaceID
        )
    }

    /// List machines enrolled in a workspace.
    public func listMachines(workspaceID: String) async throws -> [FleetMachine] {
        try await send(
            path: "v1/fleet/machines",
            method: "GET",
            workspaceID: workspaceID
        )
    }

    /// Get one machine enrolled in a workspace.
    public func getMachine(id: String, workspaceID: String) async throws -> FleetMachine {
        try await send(
            path: "v1/fleet/machines/\(id)",
            method: "GET",
            workspaceID: workspaceID
        )
    }

    /// List one cursor-based page of runner jobs, newest first.
    public func listJobs(
        workspaceID: String,
        machineID: String? = nil,
        status: FleetRunnerJobStatus? = nil,
        cursor: String? = nil,
        limit: Int? = nil
    ) async throws -> FleetRunnerJobPage {
        var queryItems: [URLQueryItem] = []
        if let machineID {
            queryItems.append(URLQueryItem(name: "machine_id", value: machineID))
        }
        if let status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }

        return try await send(
            path: "v1/fleet/jobs",
            method: "GET",
            workspaceID: workspaceID,
            queryItems: queryItems
        )
    }

    /// Get one runner job recorded in a workspace.
    public func getJob(id: String, workspaceID: String) async throws -> FleetRunnerJob {
        try await send(
            path: "v1/fleet/jobs/\(id)",
            method: "GET",
            workspaceID: workspaceID
        )
    }

    /// Convert transport/domain errors into text suitable for the Fleet UI.
    public static func userMessage(for error: Error) -> String {
        if let error = error as? FleetPlatformError {
            return error.localizedDescription
        }
        if error is CancellationError {
            return "The Platform request was cancelled."
        }
        return error.localizedDescription
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        workspaceID: String? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let accessToken = try await accessTokenProvider.accessToken()
        let endpoint = configuration.baseURL.appending(path: path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw FleetPlatformError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw FleetPlatformError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let workspaceID {
            request.setValue(workspaceID, forHTTPHeaderField: "X-Workspace-Id")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw FleetPlatformError.transport(code: error.code)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FleetPlatformError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.apiError(statusCode: httpResponse.statusCode)
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw FleetPlatformError.malformedResponse
        }
    }

    private static func apiError(statusCode: Int) -> FleetPlatformError {
        switch statusCode {
        case 401:
            return .authenticationRequired
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 429:
            return .rateLimited
        case 500..<600:
            return .serverError(statusCode: statusCode)
        default:
            return .api(statusCode: statusCode)
        }
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = try? fractional.parse(value) {
                return date
            }
            let wholeSeconds = Date.ISO8601FormatStyle()
            if let date = try? wholeSeconds.parse(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid RFC 3339 date"
            )
        }
        return decoder
    }
}
