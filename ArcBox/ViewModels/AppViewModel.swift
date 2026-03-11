import SwiftUI

/// Main application state
@Observable
class AppViewModel {
    var currentNav: NavItem? = .containers
    var showHelperApprovalBanner = false

    func navigate(to item: NavItem) {
        currentNav = item
    }
}
