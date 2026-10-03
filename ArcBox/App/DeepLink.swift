import Foundation

/// A parsed `arcbox://` deep link.
///
/// Supported forms:
/// - `arcbox://main` (or no host) — open and activate the main window
/// - `arcbox://settings` — open the Settings window
/// - `arcbox://<section>[/<id>]` — navigate to a sidebar section, where
///   `<section>` is a `NavItem` raw value and the optional `<id>` selects the
///   resource with that exact ID. Activity and This Mac do not accept an ID.
enum DeepLink: Equatable {
    static let scheme = "arcbox"

    case main
    case settings
    case section(NavItem, id: String?)

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host()?.lowercased() ?? "" {
        case "", "main":
            self = .main
        case "settings":
            self = .settings
        case let host:
            guard let item = NavItem(rawValue: host) else { return nil }
            self = .section(item, id: url.pathComponents.first { $0 != "/" })
        }
    }

    /// The canonical URL for this link, round-tripping through `init(_:)`.
    /// Lets a link be carried through APIs that only take URLs, such as a
    /// notification's `userInfo`.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .main:
            components.host = "main"
        case .settings:
            components.host = "settings"
        case .section(let item, let id):
            components.host = item.rawValue
            if let id { components.path = "/\(id)" }
        }
        // Scheme and host are fixed vocabulary and `path` is percent-encoded on
        // assignment, so there is no input that makes this fail.
        return components.url!
    }
}
