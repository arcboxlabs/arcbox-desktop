import Foundation

/// A parsed `arcbox://` deep link.
///
/// Supported forms:
/// - `arcbox://main` (or no host) — open and activate the main window
/// - `arcbox://settings` — open the Settings window
/// - `arcbox://<section>[/<id>]` — navigate to a sidebar section, where
///   `<section>` is a `NavItem` raw value (`containers`, `volumes`, `images`,
///   `networks`, `pods`, `services`, `machines`, `sandboxes`, `templates`)
///   and the optional `<id>` selects the item with that exact ID.
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
}
