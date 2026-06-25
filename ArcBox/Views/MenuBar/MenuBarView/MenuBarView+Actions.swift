import AppKit
import ArcBoxClient
import SwiftUI

extension MenuBarView {
    // MARK: - Actions

    var actionSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuBarHoverButton(action: showArcBoxWindow) {
                Label("Show ArcBox", systemImage: "macwindow")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }

            MenuBarHoverButton(action: showSettingsWindow) {
                Label("Settings", systemImage: "gear")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }

            Divider()
                .padding(.vertical, 4)

            MenuBarHoverButton {
                (NSApp.delegate as? AppDelegate)?.forceQuit = true
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: - Helpers

    var hasContainers: Bool {
        !displayedContainers.isEmpty
    }

    var hasStoppedContainers: Bool {
        containersVM.containers.contains { !$0.isRunning }
    }

    var displayedContainers: [ContainerViewModel] {
        containersVM.containers.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var containerListHeight: CGFloat {
        let rowCount = min(displayedContainers.count, maxVisibleContainerRows)
        let rowsHeight = CGFloat(rowCount) * containerRowHeight
        let spacingHeight = CGFloat(max(rowCount - 1, 0)) * containerRowSpacing
        return rowsHeight + spacingHeight
    }

    var maxVisibleContainerRows: Int { 8 }

    var containerRowHeight: CGFloat { 24 }

    var containerRowSpacing: CGFloat { 2 }

    var daemonStateDisplay: String {
        switch daemonManager.state {
        case .running: "Running"
        case .starting: "Starting"
        case .stopping: "Stopping"
        case .registered: "Registered"
        case .stopped: "Stopped"
        case .error: "Error"
        }
    }

    var daemonStateColor: Color {
        switch daemonManager.state {
        case .running: AppColors.running
        case .starting, .registered, .stopping: AppColors.textSecondary
        case .stopped: AppColors.stopped
        case .error: AppColors.error
        }
    }

    func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    func navigateToPage(_ item: NavItem) {
        appVM.navigate(to: item)
        showArcBoxWindow()
    }

    func showSettingsWindow() {
        if bringWindowToFront(matching: { $0.title == "Settings" }) {
            return
        }

        openWindow(id: "settings")
    }

    func showArcBoxWindow() {
        if bringWindowToFront(matching: isMainArcBoxWindow) {
            return
        }

        openWindow(id: "main")
    }

    @discardableResult
    func bringWindowToFront(matching predicate: (NSWindow) -> Bool) -> Bool {
        guard let window = NSApp.windows.first(where: predicate) else {
            return false
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func isMainArcBoxWindow(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled), !(window is NSPanel) else {
            return false
        }

        return window.title == "ArcBox"
    }
}
