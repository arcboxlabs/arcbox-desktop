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

    /// Creates a new client from a parsed kubeconfig.
    public init(config: KubeConfig) throws {
        self.session = try config.makeURLSession()
        self.baseURL = config.server
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

    // MARK: - Private

    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw K8sError.invalidURL(baseURL + path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
    static let kubernetes: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = isoFormatter.date(from: string) {
                return date
            }
            // ISO8601DateFormatter only handles up to 3 fractional digits;
            // truncate longer precision (e.g. nanoseconds) before parsing.
            let normalized = truncateFractionalSeconds(string)
            if let date = isoFractionalFormatter.date(from: normalized) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()

    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
    nonisolated(unsafe) private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Truncate fractional seconds to 3 digits so ISO8601DateFormatter can parse them.
    /// e.g. "2026-01-01T00:00:00.123456789Z" → "2026-01-01T00:00:00.123Z"
    private static func truncateFractionalSeconds(_ s: String) -> String {
        guard let dotIndex = s.firstIndex(of: ".") else { return s }
        let afterDot = s.index(after: dotIndex)
        guard afterDot < s.endIndex else { return s }
        // Find where the fractional digits end (next non-digit)
        let fracEnd = s[afterDot...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
        let fracCount = s.distance(from: afterDot, to: fracEnd)
        guard fracCount > 3 else { return s }
        let keepEnd = s.index(afterDot, offsetBy: 3)
        return String(s[..<keepEnd]) + String(s[fracEnd...])
    }
}
