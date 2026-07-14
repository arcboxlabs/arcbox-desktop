import Foundation

/// Identifies the OIDC provider the app authenticates against.
///
/// Only the issuer and client ID vary per environment; the redirect URI and
/// scopes are facts about this app and are compiled in. All other endpoints
/// are discovered at runtime from `{issuer}/.well-known/openid-configuration`.
///
/// To develop against a local IdP before the platform provider is registered,
/// run Dex with a static client shaped exactly like this (Dex rejects
/// custom-scheme redirect URIs unless they are listed explicitly):
///
/// ```yaml
/// staticClients:
///   - id: arcbox-desktop
///     name: ArcBox Desktop
///     public: true
///     redirectURIs:
///       - com.arcboxlabs.desktop:/oauth2redirect
/// ```
///
/// then point your `Local.xcconfig` at it:
///
/// ```
/// OIDC_ISSUER_URL = http://localhost:5556/dex
/// OIDC_CLIENT_ID = arcbox-desktop
/// ```
public struct OIDCClientConfiguration: Sendable, Equatable {
    public let issuerURL: URL
    public let clientID: String

    /// Registered with the platform IdP; changing it requires coordinated
    /// re-registration server-side, so treat it as stable once shipped.
    public static let redirectURI = URL(string: "com.arcboxlabs.desktop:/oauth2redirect")!
    public static let scopes = ["openid", "profile", "email", "offline_access"]

    public init(issuerURL: URL, clientID: String) {
        self.issuerURL = issuerURL
        self.clientID = clientID
    }

    /// Inert default used when no issuer is configured: `.invalid` is an
    /// RFC 2606 reserved TLD, so sign-in fails fast with a clear error
    /// instead of reaching a live host.
    public static let placeholder = OIDCClientConfiguration(
        issuerURL: URL(string: "https://auth.arcbox.invalid")!,
        clientID: "arcbox-desktop-placeholder"
    )

    /// Configuration resolved from Info.plist (`OIDCIssuerURL`/`OIDCClientID`,
    /// injected via the `OIDC_ISSUER_URL`/`OIDC_CLIENT_ID` build settings),
    /// falling back to `.placeholder` when unconfigured.
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
    static func resolve(issuer: String?, clientID: String?) -> OIDCClientConfiguration? {
        guard let issuer = configuredValue(issuer),
            let clientID = configuredValue(clientID),
            let issuerURL = URL(string: issuer)
        else { return nil }
        return OIDCClientConfiguration(issuerURL: issuerURL, clientID: clientID)
    }

    private static func configuredValue(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("$("), !raw.hasPrefix("YOUR_") else { return nil }
        return raw
    }
}
