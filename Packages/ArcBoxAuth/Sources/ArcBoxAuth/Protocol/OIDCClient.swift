import Foundation

/// URLSession-backed implementation of the OIDC protocol calls.
public final class OIDCClient: OIDCProviding, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func discover(issuer: URL) async throws -> OIDCEndpoints {
        let url = issuer.appending(path: ".well-known/openid-configuration")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, status) = try await perform(request)
        guard status == 200 else {
            throw OIDCError.discoveryFailed("HTTP \(status) from \(url.absoluteString)")
        }
        do {
            return try JSONDecoder().decode(OIDCEndpoints.self, from: data)
        } catch {
            throw OIDCError.discoveryFailed("malformed discovery document")
        }
    }

    public func exchangeCode(
        _ code: String,
        verifier: String,
        configuration: OIDCClientConfiguration,
        endpoints: OIDCEndpoints
    ) async throws -> TokenResponse {
        try await tokenRequest(
            endpoints.tokenEndpoint,
            fields: [
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": verifier,
                "client_id": configuration.clientID,
                "redirect_uri": OIDCClientConfiguration.redirectURI.absoluteString,
            ])
    }

    public func refresh(
        refreshToken: String,
        configuration: OIDCClientConfiguration,
        endpoints: OIDCEndpoints
    ) async throws -> TokenResponse {
        try await tokenRequest(
            endpoints.tokenEndpoint,
            fields: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": configuration.clientID,
            ])
    }

    public func revoke(
        token: String,
        tokenTypeHint: String,
        configuration: OIDCClientConfiguration,
        endpoint: URL
    ) async throws {
        let (data, status) = try await post(
            endpoint,
            fields: [
                "token": token,
                "token_type_hint": tokenTypeHint,
                "client_id": configuration.clientID,
            ])
        guard (200..<300).contains(status) else {
            throw OIDCError.tokenRequestFailed(
                status: status, body: String(bytes: data, encoding: .utf8) ?? "")
        }
    }

    public func userInfo(accessToken: String, endpoint: URL) async throws -> OIDCUserInfo {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, status) = try await perform(request)
        return try Self.decodeUserInfo(data: data, status: status)
    }

    // MARK: - Internal (unit-tested via @testable)

    static func decodeUserInfo(data: Data, status: Int) throws -> OIDCUserInfo {
        guard status == 200 else {
            throw OIDCError.userInfoFailed(
                status: status, body: String(bytes: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(OIDCUserInfo.self, from: data)
        } catch {
            throw OIDCError.userInfoFailed(status: status, body: "malformed userinfo response")
        }
    }

    static func decodeTokenResponse(data: Data, status: Int) throws -> TokenResponse {
        guard (200..<300).contains(status) else {
            throw OIDCError.tokenRequestFailed(
                status: status, body: String(bytes: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw OIDCError.tokenRequestFailed(status: status, body: "malformed token response")
        }
    }

    /// `application/x-www-form-urlencoded` body; keys sorted for determinism.
    static func formBody(_ fields: [String: String]) -> Data {
        let pairs = fields.sorted { $0.key < $1.key }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    // MARK: - Private

    private func tokenRequest(_ url: URL, fields: [String: String]) async throws -> TokenResponse {
        let (data, status) = try await post(url, fields: fields)
        return try Self.decodeTokenResponse(data: data, status: status)
    }

    private func post(_ url: URL, fields: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(fields)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OIDCError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw OIDCError.network("non-HTTP response")
        }
        return (data, http.statusCode)
    }
}
