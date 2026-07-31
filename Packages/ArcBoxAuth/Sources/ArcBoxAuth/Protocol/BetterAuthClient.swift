import Foundation

/// URLSession-backed implementation of the Better Auth calls.
///
/// All endpoints accept JSON request bodies and answer JSON; errors follow
/// RFC 8628 (`{"error": ..., "error_description": ...}` with HTTP 400).
public final class BetterAuthClient: AuthProviding, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func requestDeviceCode(
        configuration: AuthClientConfiguration
    ) async throws -> DeviceCodeGrant {
        let (data, status) = try await post(
            configuration.deviceCodeEndpoint,
            body: ["client_id": configuration.clientID])
        return try Self.decodeDeviceCodeGrant(data: data, status: status)
    }

    public func pollDeviceToken(
        deviceCode: String,
        configuration: AuthClientConfiguration
    ) async throws -> DevicePollOutcome {
        let (data, status) = try await post(
            configuration.deviceTokenEndpoint,
            body: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": deviceCode,
                "client_id": configuration.clientID,
            ])
        return try Self.decodePollOutcome(data: data, status: status)
    }

    public func session(
        token: String,
        configuration: AuthClientConfiguration
    ) async throws -> SessionSnapshot? {
        var request = URLRequest(url: configuration.sessionEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, status) = try await perform(request)
        return try Self.decodeSessionSnapshot(data: data, status: status)
    }

    public func signOut(
        token: String,
        configuration: AuthClientConfiguration
    ) async throws {
        var request = URLRequest(url: configuration.signOutEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else {
            throw AuthError.requestFailed(status: status, body: Self.truncated(data))
        }
    }

    // MARK: - Internal (unit-tested via @testable)

    static func decodeDeviceCodeGrant(data: Data, status: Int) throws -> DeviceCodeGrant {
        guard status == 200 else {
            throw AuthError.requestFailed(status: status, body: truncated(data))
        }
        do {
            return try JSONDecoder().decode(DeviceCodeGrant.self, from: data)
        } catch {
            throw AuthError.malformedResponse("malformed device authorization response")
        }
    }

    static func decodePollOutcome(data: Data, status: Int) throws -> DevicePollOutcome {
        if status == 200 {
            guard let success = try? JSONDecoder().decode(TokenSuccess.self, from: data) else {
                throw AuthError.malformedResponse("malformed device token response")
            }
            return .granted(
                DeviceTokenGrant(
                    sessionToken: success.accessToken,
                    expiresAt: success.expiresIn.map { Date(timeIntervalSinceNow: $0) }
                ))
        }
        guard let failure = try? JSONDecoder().decode(TokenFailure.self, from: data) else {
            throw AuthError.requestFailed(status: status, body: truncated(data))
        }
        switch failure.error {
        case "authorization_pending":
            return .authorizationPending
        case "slow_down":
            return .slowDown
        case "access_denied":
            throw AuthError.authorizationDenied
        case "expired_token":
            throw AuthError.deviceCodeExpired
        default:
            throw AuthError.requestFailed(
                status: status, body: failure.errorDescription ?? failure.error)
        }
    }

    static func decodeSessionSnapshot(data: Data, status: Int) throws -> SessionSnapshot? {
        switch status {
        case 200:
            let body = String(bytes: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let body, !body.isEmpty, body != "null" else { return nil }
            do {
                return try decoder.decode(SessionSnapshot.self, from: data)
            } catch {
                throw AuthError.malformedResponse("malformed session response")
            }
        case 401, 403:
            return nil
        default:
            throw AuthError.requestFailed(status: status, body: truncated(data))
        }
    }

    /// Caps response bodies carried inside errors so provider responses
    /// never flood logs or the UI.
    static func truncated(_ data: Data, limit: Int = 200) -> String {
        let body = String(bytes: data, encoding: .utf8) ?? ""
        return body.count <= limit ? body : String(body.prefix(limit)) + "…"
    }

    // MARK: - Private

    /// RFC 3339 timestamps, with or without fractional seconds.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
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
    }()

    private func post(_ url: URL, body: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("non-HTTP response")
        }
        return (data, http.statusCode)
    }
}

private struct TokenSuccess: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

private struct TokenFailure: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
