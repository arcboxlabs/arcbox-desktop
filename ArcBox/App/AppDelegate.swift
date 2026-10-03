import AppKit
import Foundation

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private(set) var coordinator: ApplicationCoordinator?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    /// Whether this process is the host of a test run rather than the app a user launched.
    ///
    /// XCTest is loaded into the host before `main` runs, so its presence is the signal. A
    /// host that boots the app installs the helper, opens Fleet connections and reads the
    /// sign-in item from the login keychain, and `make test` signs the host ad hoc, so that
    /// read prompted for the keychain password on every build.
    nonisolated static let isTestHost = NSClassFromString("XCTestCase") != nil

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppPreferences.registerDefaults()
        installMainMenu()
        guard !Self.isTestHost else { return }
        Self.initSentry()
        Self.initPostHog()
        coordinator = ApplicationCoordinator()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let coordinator else { return }
        coordinator.start()
        coordinator.showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard coordinator?.isTerminating != true else { return }
        urls.forEach { coordinator?.handleDeepLink($0) }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard coordinator?.isTerminating != true else { return false }
        coordinator?.showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator else { return .terminateNow }
        guard coordinator.beginTermination() else { return .terminateLater }
        Task {
            await coordinator.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard coordinator?.isTerminating != true else { return false }
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return coordinator?.canCheckForUpdates == true
        }
        if menuItem.action == #selector(showSettings(_:))
            || menuItem.action == #selector(showGettingStarted(_:))
        {
            return coordinator?.canUseMainInterface == true
        }
        return true
    }

    @objc private func showAbout(_ sender: Any?) {
        coordinator?.showAbout()
    }

    @objc private func showSettings(_ sender: Any?) {
        coordinator?.showSettings()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        coordinator?.checkForUpdates()
    }

    @objc private func showGettingStarted(_ sender: Any?) {
        coordinator?.showGettingStarted()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let fileItem = NSMenuItem()
        let editItem = NSMenuItem()
        let viewItem = NSMenuItem()
        let windowItem = NSMenuItem()
        let helpItem = NSMenuItem()

        mainMenu.addItem(appItem)
        mainMenu.addItem(fileItem)
        mainMenu.addItem(editItem)
        mainMenu.addItem(viewItem)
        mainMenu.addItem(windowItem)
        mainMenu.addItem(helpItem)

        appItem.submenu = makeApplicationMenu()
        fileItem.submenu = makeFileMenu()
        editItem.submenu = makeEditMenu()
        viewItem.submenu = makeViewMenu()
        let windowMenu = makeWindowMenu()
        windowItem.submenu = windowMenu
        let helpMenu = makeHelpMenu()
        helpItem.submenu = helpMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    private func makeApplicationMenu() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: appName)

        menu.addItem(item("About \(appName)", action: #selector(showAbout(_:))))
        menu.addItem(item("Check for Updates…", action: #selector(checkForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(
            item(
                "Settings…",
                action: #selector(showSettings(_:)),
                key: ","
            ))
        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        menu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        menu.addItem(.separator())
        menu.addItem(
            item(
                "Hide \(appName)",
                action: #selector(NSApplication.hide(_:)),
                key: "h",
                target: NSApp
            ))
        let hideOthers = item(
            "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            target: NSApp
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            item(
                "Show All",
                action: #selector(NSApplication.unhideAllApplications(_:)),
                target: NSApp
            ))

        menu.addItem(.separator())
        menu.addItem(
            item(
                "Quit \(appName)",
                action: #selector(NSApplication.terminate(_:)),
                key: "q",
                target: NSApp
            ))
        return menu
    }

    private func makeFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(
            responderItem(
                "Close Window",
                action: #selector(NSWindow.performClose(_:)),
                key: "w"
            ))
        return menu
    }

    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(responderItem("Undo", action: Selector(("undo:")), key: "z"))
        let redo = responderItem("Redo", action: Selector(("redo:")), key: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(responderItem("Cut", action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(responderItem("Copy", action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(responderItem("Paste", action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(
            responderItem("Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private func makeViewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        let toggleSidebar = responderItem(
            "Toggle Sidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            key: "s"
        )
        toggleSidebar.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(toggleSidebar)
        return menu
    }

    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(
            responderItem(
                "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)),
                key: "m"
            ))
        menu.addItem(responderItem("Zoom", action: #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(
            item(
                "Bring All to Front",
                action: #selector(NSApplication.arrangeInFront(_:)),
                target: NSApp
            ))
        return menu
    }

    private func makeHelpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(
            item(
                "Getting Started with ArcBox",
                action: #selector(showGettingStarted(_:))
            ))
        return menu
    }

    private func item(
        _ title: String,
        action: Selector?,
        key: String = "",
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private func responderItem(
        _ title: String,
        action: Selector,
        key: String = ""
    ) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
