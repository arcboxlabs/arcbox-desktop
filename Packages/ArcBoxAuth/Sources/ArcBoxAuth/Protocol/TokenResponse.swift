import Foundation

/// Token-endpoint response (RFC 6749 §5.1).
public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let tokenType: String
    /// Seconds until the access token expires; RECOMMENDED in the spec, so optional.
    public let expiresIn: TimeInterval?
    /// Only present when the provider grants offline access.
    public let refreshToken: String?
    public let idToken: String?
    public let scope: String?

    public init(
        accessToken: String,
        tokenType: String = "bearer",
        expiresIn: TimeInterval? = nil,
        refreshToken: String? = nil,
        idToken: String? = nil,
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case scope
    }
}
