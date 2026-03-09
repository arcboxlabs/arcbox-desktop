import SwiftUI
import AppKit
import ArcBoxClient
import DockerClient
import Sparkle

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?
    var eventMonitor: DockerEventMonitor?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        eventMonitor?.stop()
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
    @State private var dockerToolSetupManager = DockerToolSetupManager()
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient?
    @State private var eventMonitor = DockerEventMonitor()

    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(bootAssetManager)
                .environment(dockerToolSetupManager)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appDelegate.daemonManager = daemonManager
                    appDelegate.eventMonitor = eventMonitor

                    // 1. Seed boot-assets from bundle → ~/.arcbox/boot/
                    await bootAssetManager.ensureAssets()

                    // 1.5. Register CLI into PATH and install shell completions.
                    // Runs after boot-assets so the CLI binary is available.
                    // Failures are non-fatal — users can run `arcbox setup install` manually.
                    if let cli = try? CLIRunner() {
                        try? await cli.run(arguments: ["setup", "install"])
                    }

                    // 1.6. Install Docker CLI tools and set arcbox as default context.
                    // Uses NDJSON streaming for progress — UI can observe
                    // dockerToolSetupManager.state.
                    await dockerToolSetupManager.installAndEnable()

                    // 2. Start health monitoring; if daemon is already registered
                    // via LaunchAgent, it will be detected automatically.
                    daemonManager.startMonitoring()

                    // 3. Register via SMAppService to ensure launchd management.
                    // register() is idempotent and also polls for reachability.
                    await daemonManager.enableDaemon()

                    // 4. Initialize clients when daemon is running
                    initClientsIfNeeded()

                    // 5. Background: check for boot-asset updates after a delay.
                    // Uses child Task (not .detached) so it's cancelled when .task tears down.
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        await bootAssetManager.checkForUpdates()
                    }
                }
                // Re-create clients whenever daemon transitions to running
                // (covers the case where monitoring detects the daemon after
                // the initial .task check has already passed).
                .onChange(of: daemonManager.state) { _, newState in
                    if newState.isRunning {
                        initClientsIfNeeded()
                        if let dockerClient {
                            eventMonitor.start(docker: dockerClient)
                        }
                    } else {
                        eventMonitor.stop()
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }

    private func initClientsIfNeeded() {
        guard daemonManager.state.isRunning else { return }

        if dockerClient == nil {
            dockerClient = DockerClient()
        }

        if arcboxClient == nil {
            do {
                let client = try ArcBoxClient()
                Task { try await client.runConnections() }
                arcboxClient = client
            } catch {}
        }
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
