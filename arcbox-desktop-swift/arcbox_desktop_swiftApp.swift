import AppKit
import ArcBoxClient
import DockerClient
import SwiftUI

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let keepRunning = UserDefaults.standard.bool(forKey: "keepRunning")
        return !keepRunning
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let daemonManager else { return .terminateNow }
        Task { @MainActor in
            daemonManager.stopMonitoring()
            await daemonManager.disableDaemon()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

// MARK: - App

@main
struct ArcBoxDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appVM = AppViewModel()
    @State private var daemonManager = DaemonManager()
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient?
    @AppStorage("showInMenuBar") private var showInMenuBar = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appDelegate.daemonManager = daemonManager

                    // Start health monitoring; if daemon is already registered
                    // via LaunchAgent, it will be detected automatically.
                    daemonManager.startMonitoring()

                    // Always register via SMAppService to ensure launchd management.
                    // register() is idempotent and also polls for reachability.
                    await daemonManager.enableDaemon()

                    // Initialize clients when daemon is running
                    if daemonManager.state.isRunning {
                        dockerClient = DockerClient()

                        do {
                            let client = try ArcBoxClient()
                            Task { try await client.runConnections() }
                            arcboxClient = client
                        } catch {}

                        // Post after next run loop so SwiftUI propagates the new dockerClient environment
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
                        }
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            SettingsCommands()
        }

        Window("", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra("ArcBox", systemImage: "shippingbox.fill", isInserted: $showInMenuBar) {
            MenuBarContentView()
        }
    }
}

// MARK: - Settings Menu Command

struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")
        }
    }
}

// MARK: - Menu Bar Content

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open ArcBox") {
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Settings...") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit ArcBox") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Environment Keys

private struct ArcBoxClientKey: EnvironmentKey {
    static let defaultValue: ArcBoxClient? = nil
}

private struct DockerClientKey: EnvironmentKey {
    static let defaultValue: DockerClient? = nil
}

extension EnvironmentValues {
    var arcboxClient: ArcBoxClient? {
        get { self[ArcBoxClientKey.self] }
        set { self[ArcBoxClientKey.self] = newValue }
    }

    var dockerClient: DockerClient? {
        get { self[DockerClientKey.self] }
        set { self[DockerClientKey.self] = newValue }
    }
}
