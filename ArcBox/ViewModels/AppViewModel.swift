import SwiftUI

/// Main application state
@MainActor
@Observable
class AppViewModel {
    var currentNav: NavItem? = .containers
    /// Selected Settings tab, lifted here so other windows can deep-link
    /// (e.g. the sidebar account chip opening Settings > Account).
    var settingsTab: SettingsTab? = .general

    func navigate(to item: NavItem) {
        currentNav = item
    }
}
