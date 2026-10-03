import Foundation

/// Resolves the ArcBox Platform API endpoint independently of OIDC discovery.
public struct FleetPlatformConfiguration: Sendable, Equatable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public static let production = FleetPlatformConfiguration(
        baseURL: URL(string: "https://api.arcbox.dev")!
    )

    /// Configuration injected through `FleetPlatformBaseURL` in Info.plist.
    /// Production is the safe default because this client performs no work
    /// until an authenticated call is explicitly requested.
    public static let current =
        resolve(
            baseURL: Bundle.main.object(forInfoDictionaryKey: "FleetPlatformBaseURL") as? String
        ) ?? .production

    static func resolve(baseURL: String?) -> FleetPlatformConfiguration? {
        guard let baseURL = configuredValue(baseURL),
            let url = URL(string: baseURL),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host() != nil
        else { return nil }

        return FleetPlatformConfiguration(baseURL: url)
    }

    private static func configuredValue(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("$("), !raw.hasPrefix("YOUR_") else {
            return nil
        }
        return raw
    }
}
