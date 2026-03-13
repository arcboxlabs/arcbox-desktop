import AppKit
import ArcBoxClient
import DockerClient
import ServiceManagement
import Sparkle
import SwiftUI

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?
    var helperManager: HelperManager?
    var eventMonitor: DockerEventMonitor?
    var isUninstalling = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        eventMonitor?.stop()
        guard let daemonManager else { return .terminateNow }

        Task { @MainActor in
            daemonManager.stopMonitoring()

            if isUninstalling, let helperManager {
                // Teardown must complete before daemon is stopped, so that
                // each helper operation can confirm the current state.
                try? await helperManager.teardownDockerSocket()
                try? await helperManager.uninstallCLITools()
                try? await helperManager.teardownDNSResolver()
                try? await SMAppService.daemon(
                    plistName: "io.arcbox.desktop.helper.plist"
                ).unregister()
            }

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
    @State private var helperManager = HelperManager()
    @State private var bootAssetManager = BootAssetManager()
    @State private var dockerToolSetupManager = DockerToolSetupManager()
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient?
    @State private var eventMonitor = DockerEventMonitor()
    @State private var startupOrchestrator: StartupOrchestrator?

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
                .environment(\.startupOrchestrator, startupOrchestrator)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appDelegate.daemonManager = daemonManager
                    appDelegate.helperManager = helperManager
                    appDelegate.eventMonitor = eventMonitor

                    let orchestrator = StartupOrchestrator(
                        bootAssetManager: bootAssetManager,
                        helperManager: helperManager,
                        daemonManager: daemonManager,
                        dockerToolSetupManager: dockerToolSetupManager,
                        onClientsNeeded: { initClientsIfNeeded() }
                    )
                    startupOrchestrator = orchestrator
                    await orchestrator.start()

                    Task {
                        try? await Task.sleep(for: StartupConstants.updateCheckDelay)
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

private struct StartupOrchestratorKey: EnvironmentKey {
    static let defaultValue: StartupOrchestrator? = nil
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

    var startupOrchestrator: StartupOrchestrator? {
        get { self[StartupOrchestratorKey.self] }
        set { self[StartupOrchestratorKey.self] = newValue }
    }
}
