import SwiftUI
import AppKit
import ArcBoxClient
import DockerClient

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?

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
    @State private var bootAssetManager = BootAssetManager()
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(bootAssetManager)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appDelegate.daemonManager = daemonManager

                    // 1. Seed boot-assets from bundle → ~/.arcbox/boot/
                    await bootAssetManager.ensureAssets()

                    // 2. Start health monitoring; if daemon is already registered
                    // via LaunchAgent, it will be detected automatically.
                    daemonManager.startMonitoring()

                    // 3. Register via SMAppService to ensure launchd management.
                    // register() is idempotent and also polls for reachability.
                    await daemonManager.enableDaemon()

                    // 4. Initialize clients when daemon is running
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

                    // 5. Background: check for boot-asset updates after a delay
                    Task.detached {
                        try? await Task.sleep(for: .seconds(5))
                        await bootAssetManager.checkForUpdates()
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
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
