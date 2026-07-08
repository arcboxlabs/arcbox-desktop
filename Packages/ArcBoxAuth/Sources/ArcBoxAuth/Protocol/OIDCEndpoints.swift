import Foundation

/// Endpoints advertised by the provider's discovery document
/// (`{issuer}/.well-known/openid-configuration`).
public struct OIDCEndpoints: Sendable, Equatable, Decodable {
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    /// RFC 7009 token revocation; not all providers implement it.
    public let revocationEndpoint: URL?
    public let endSessionEndpoint: URL?
    public let userinfoEndpoint: URL?

    public init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        revocationEndpoint: URL? = nil,
        endSessionEndpoint: URL? = nil,
        userinfoEndpoint: URL? = nil
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.endSessionEndpoint = endSessionEndpoint
        self.userinfoEndpoint = userinfoEndpoint
    }

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case endSessionEndpoint = "end_session_endpoint"
        case userinfoEndpoint = "userinfo_endpoint"
    }
}
