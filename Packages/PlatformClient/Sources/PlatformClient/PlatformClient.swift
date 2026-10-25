// Foundation precedes local packages per the repository import-order guideline.
// swift-format-ignore: OrderedImports
import Foundation
import ArcBoxAuth

protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {}

/// Authenticated REST client for the Platform operations needed by runner host enrollment.
public final class PlatformClient: Sendable {
    private let configuration: PlatformConfiguration
    private let accessTokenProvider: any AccessTokenProviding
    private let http: any HTTPDataLoading

    public init(
        configuration: PlatformConfiguration = .current,
        accessTokenProvider: any AccessTokenProviding,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
        self.http = session
    }

    init(
        configuration: PlatformConfiguration,
        accessTokenProvider: any AccessTokenProviding,
        http: any HTTPDataLoading
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
        self.http = http
    }

    /// List workspaces the current Platform identity belongs to.
    public func listWorkspaces() async throws -> [PlatformWorkspace] {
        try await send(path: "v1/workspaces", method: "GET")
    }

    /// Create and return the workspace's one-hour runner enrollment token,
    /// invalidating any token previously issued for the workspace.
    public func createEnrollmentToken(workspaceID: String) async throws -> RunnerEnrollmentToken {
        try await send(
            path: "v1/runners/enrollment-token",
            method: "POST",
            workspaceID: workspaceID
        )
    }

    /// Convert transport/domain errors into text suitable for the Runners UI.
    public static func userMessage(for error: Error) -> String {
        if let error = error as? PlatformError {
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw PlatformError.transport(code: error.code)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlatformError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.apiError(statusCode: httpResponse.statusCode)
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw PlatformError.malformedResponse
        }
    }

    private static func apiError(statusCode: Int) -> PlatformError {
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
