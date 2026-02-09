import SwiftUI

/// Main application state
@Observable
class AppViewModel {
    var currentNav: NavItem = .containers
    var sidebarCollapsed: Bool = false
    var sidebarWidth: CGFloat = 180

    func navigate(to item: NavItem) {
        currentNav = item
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            sidebarCollapsed.toggle()
        }
    }
}
