import Foundation

/// Identifies the Better Auth identity provider the app authenticates
/// against via the OAuth 2.0 device-authorization grant (RFC 8628).
///
/// Only the provider base URL and client ID vary per environment. All
/// endpoints are fixed paths under the base URL — the device endpoints are
/// registered by the provider's `deviceAuthorization()` plugin and are not
/// part of OIDC discovery.
public struct AuthClientConfiguration: Sendable, Equatable {
    /// Better Auth base URL, e.g. `https://auth.arcbox.dev/api/auth`.
    public let issuerURL: URL
    public let clientID: String

    public init(issuerURL: URL, clientID: String) {
        self.issuerURL = issuerURL
        self.clientID = clientID
    }

    var deviceCodeEndpoint: URL { issuerURL.appending(path: "device/code") }
    var deviceTokenEndpoint: URL { issuerURL.appending(path: "device/token") }
    var sessionEndpoint: URL { issuerURL.appending(path: "get-session") }
    var signOutEndpoint: URL { issuerURL.appending(path: "sign-out") }

    /// Inert default used when no provider is configured: `.invalid` is an
    /// RFC 2606 reserved TLD, so sign-in fails fast with a clear error
    /// instead of reaching a live host.
    public static let placeholder = AuthClientConfiguration(
        issuerURL: URL(string: "https://auth.arcbox.invalid")!,
        clientID: "arcbox-desktop-placeholder"
    )

    /// Configuration resolved from Info.plist (`OIDCIssuerURL`/`OIDCClientID`,
    /// injected via the `OIDC_ISSUER_URL`/`OIDC_CLIENT_ID` build settings),
    /// falling back to `.placeholder` when unconfigured. The key names
    /// predate the device-grant flow and stay stable so existing build
    /// configurations and CI keep working.
    public static let current =
        resolve(
            issuer: Bundle.main.object(forInfoDictionaryKey: "OIDCIssuerURL") as? String,
            clientID: Bundle.main.object(forInfoDictionaryKey: "OIDCClientID") as? String
        ) ?? .placeholder

    public var isPlaceholder: Bool { self == .placeholder }

    /// Short label for the Account UI describing which provider is in use.
    public var environmentLabel: String {
        if isPlaceholder { return "Not Configured" }
        guard let host = issuerURL.host() else { return issuerURL.absoluteString }
        if host == "localhost" || host == "127.0.0.1" { return "Local" }
        return host
    }

    /// Treats empty strings, unexpanded `$(VAR)` references, and
    /// `YOUR_..._HERE` sentinels as unconfigured — the same guard the
    /// Sentry/PostHog Info.plist keys use.
    static func resolve(issuer: String?, clientID: String?) -> AuthClientConfiguration? {
        guard let issuer = configuredValue(issuer),
            let clientID = configuredValue(clientID),
            let issuerURL = URL(string: issuer)
        else { return nil }
        return AuthClientConfiguration(issuerURL: issuerURL, clientID: clientID)
    }

    private static func configuredValue(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("$("), !raw.hasPrefix("YOUR_") else { return nil }
        return raw
    }
}
