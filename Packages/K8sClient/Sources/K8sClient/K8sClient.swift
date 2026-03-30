import Foundation

/// HTTP client for communicating with the Kubernetes API server.
///
/// Usage:
/// ```swift
/// let config = try KubeConfig(yaml: kubeconfigYAML)
/// let client = try K8sClient(config: config)
/// let pods = try await client.listPods(namespace: "default")
/// ```
@available(macOS 15.0, *)
public final class K8sClient: Sendable {
    private let session: URLSession
    private let baseURL: String
    private let bearerToken: String?

    /// Creates a new client from a parsed kubeconfig.
    public init(config: KubeConfig) throws {
        self.session = try config.makeURLSession()
        self.baseURL = config.server
        if case .bearerToken(let token) = config.authMode {
            self.bearerToken = token
        } else {
            self.bearerToken = nil
        }
    }

    // MARK: - Pods

    public func listPods(namespace: String = "default") async throws -> PodList {
        try await get("/api/v1/namespaces/\(namespace)/pods")
    }

    public func listAllPods() async throws -> PodList {
        try await get("/api/v1/pods")
    }

    // MARK: - Services

    public func listServices(namespace: String = "default") async throws -> ServiceList {
        try await get("/api/v1/namespaces/\(namespace)/services")
    }

    public func listAllServices() async throws -> ServiceList {
        try await get("/api/v1/services")
    }

    // MARK: - Watch (TODO: implement streaming watch with reconnection)
    //
    // Future: implement watch using chunked HTTP response with:
    // - resourceVersion tracking from list metadata
    // - Automatic reconnection with exponential backoff
    // - ADDED/MODIFIED/DELETED event types
    // See: https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes

    // MARK: - Private

    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw K8sError.invalidURL(baseURL + path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try JSONDecoder.kubernetes.decode(T.self, from: data)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw K8sError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw K8sError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

public enum K8sError: Error, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
}

// MARK: - JSON Decoder

extension JSONDecoder {
    /// Decoder configured for Kubernetes API JSON (ISO 8601 dates).
    /// Uses `Date.ISO8601FormatStyle` (Sendable) instead of `ISO8601DateFormatter`.
    static let kubernetes: JSONDecoder = {
        let decoder = JSONDecoder()
        let isoStrategy = Date.ISO8601FormatStyle()
        let isoFracStrategy = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? isoStrategy.parse(string) {
                return date
            }
            // ISO8601FormatStyle only handles up to 3 fractional digits;
            // truncate longer precision (e.g. nanoseconds) before parsing.
            let normalized = truncateFractionalSeconds(string)
            if let date = try? isoFracStrategy.parse(normalized) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()

    /// Truncate fractional seconds to 3 digits for ISO 8601 parsing.
    /// e.g. "2026-01-01T00:00:00.123456789Z" → "2026-01-01T00:00:00.123Z"
    private static func truncateFractionalSeconds(_ s: String) -> String {
        guard let dotIndex = s.firstIndex(of: ".") else { return s }
        let afterDot = s.index(after: dotIndex)
        guard afterDot < s.endIndex else { return s }
        let fracEnd = s[afterDot...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
        let fracCount = s.distance(from: afterDot, to: fracEnd)
        guard fracCount > 3 else { return s }
        let keepEnd = s.index(afterDot, offsetBy: 3)
        return String(s[..<keepEnd]) + String(s[fracEnd...])
    }
}
