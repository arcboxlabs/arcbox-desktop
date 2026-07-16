import Foundation

/// Protocol-level OIDC operations, abstracted so `AuthSession` can be tested
/// against a fake provider.
public protocol OIDCProviding: Sendable {
    func discover(issuer: URL) async throws -> OIDCEndpoints

    func exchangeCode(
        _ code: String,
        verifier: String,
        configuration: OIDCClientConfiguration,
        endpoints: OIDCEndpoints
    ) async throws -> TokenResponse

    func refresh(
        refreshToken: String,
        configuration: OIDCClientConfiguration,
        endpoints: OIDCEndpoints
    ) async throws -> TokenResponse

    /// RFC 7009 revocation. Best-effort: callers decide whether to surface failures.
    func revoke(
        token: String,
        tokenTypeHint: String,
        configuration: OIDCClientConfiguration,
        endpoint: URL
    ) async throws

    /// OIDC Core §5.3 userinfo request with a Bearer access token.
    func userInfo(accessToken: String, endpoint: URL) async throws -> OIDCUserInfo
}
