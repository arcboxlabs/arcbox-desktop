import SwiftUI

/// Main application state
@MainActor
@Observable
class AppViewModel {
    var currentNav: NavItem? = .containers

    func navigate(to item: NavItem) {
        currentNav = item
    }
}
