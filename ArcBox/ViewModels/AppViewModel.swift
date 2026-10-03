import Observation

/// Main application state
@MainActor
@Observable
class AppViewModel {
    enum DockerContextRetry {
        case lifecycle(useArcBox: Bool)
        case preference(enabled: Bool)

        var useArcBox: Bool {
            switch self {
            case let .lifecycle(useArcBox): useArcBox
            case let .preference(enabled): enabled
            }
        }
    }

    struct ResourceDeepLink: Equatable {
        let section: NavItem
        let id: String
        let requestedAt: ContinuousClock.Instant
    }

    var currentNav: NavItem? = .containers
    /// Selected Settings tab, lifted here so other windows can deep-link
    /// (e.g. the sidebar account chip opening Settings > Account).
    var settingsTab: SettingsTab? = .general
    var pendingResourceDeepLink: ResourceDeepLink?
    var deepLinkError: String?
    var dockerContextError: String?
    var dockerContextRetry: DockerContextRetry?

    func navigate(to item: NavItem) {
        currentNav = item
    }

    func requestResourceDeepLink(section: NavItem, id: String) {
        pendingResourceDeepLink = ResourceDeepLink(
            section: section,
            id: id,
            requestedAt: ContinuousClock().now
        )
        deepLinkError = nil
    }

    func clearResourceDeepLink() {
        pendingResourceDeepLink = nil
        deepLinkError = nil
    }

    @discardableResult
    func resolveResourceDeepLink(
        availableIDs: Set<String>,
        isLoaded: Bool
    ) -> ResourceDeepLink? {
        guard let request = pendingResourceDeepLink else { return nil }
        guard isLoaded else { return nil }
        if availableIDs.contains(request.id) {
            pendingResourceDeepLink = nil
            return request
        }
        pendingResourceDeepLink = nil
        deepLinkError = "Resource “\(request.id)” wasn’t found in \(request.section.label)."
        return nil
    }
}
