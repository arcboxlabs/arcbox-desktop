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
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient?

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

                    // If not yet registered, enable the daemon via SMAppService.
                    if !daemonManager.isReachable {
                        await daemonManager.enableDaemon()
                    }

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
