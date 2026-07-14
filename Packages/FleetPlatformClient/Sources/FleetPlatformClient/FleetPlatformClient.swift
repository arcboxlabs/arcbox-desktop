import ArcBoxAuth
import Foundation

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

    /// Rotate and return the workspace's one-hour Fleet enrollment token.
    public func issueEnrollmentToken(workspaceID: String) async throws -> FleetEnrollmentToken {
        try await send(
            path: "v1/fleet/enrollment-token",
            method: "POST",
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
        if let error = error as? URLError {
            return "Could not reach the ArcBox Platform: \(error.localizedDescription)"
        }
        return error.localizedDescription
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        workspaceID: String? = nil
    ) async throws -> Response {
        let accessToken = try await accessTokenProvider.accessToken()
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let workspaceID {
            request.setValue(workspaceID, forHTTPHeaderField: "X-Workspace-Id")
        }

        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FleetPlatformError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.apiError(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw FleetPlatformError.malformedResponse
        }
    }

    private static func apiError(statusCode: Int, data: Data) -> FleetPlatformError {
        let entry = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.first
        switch statusCode {
        case 401:
            return .unauthenticated
        case 403:
            return .forbidden
        case 404:
            return .notFound
        default:
            return .api(
                statusCode: statusCode,
                status: entry?.status,
                message: entry?.message ?? "ArcBox Platform request failed with HTTP \(statusCode)."
            )
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

private struct APIErrorEnvelope: Decodable {
    let error: [APIErrorEntry]
}

private struct APIErrorEntry: Decodable {
    let status: String?
    let message: String?
}
