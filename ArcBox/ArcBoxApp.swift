import SwiftUI
import AppKit
import ArcBoxClient
import DockerClient
import ServiceManagement
import Sparkle

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
                    appDelegate.helperManager = helperManager
                    appDelegate.eventMonitor = eventMonitor

                    // 1. Seed boot-assets from bundle → ~/.arcbox/boot/
                    await bootAssetManager.ensureAssets()

                    // 2. Register privileged helper (SMAppService.daemon, root-level) and run
                    //    all three privileged setup operations sequentially (each try? await,
                    //    one failure does not cancel the others). Non-fatal: core works without helper.
                    await setupHelper()

                    // 3. Register CLI into PATH and install shell completions.
                    if let cli = try? CLIRunner() {
                        try? await cli.run(arguments: ["setup", "install"])
                    }

                    // 4. Install Docker CLI tools and set arcbox as default context.
                    await dockerToolSetupManager.installAndEnable()

                    // 5. Start health monitoring.
                    daemonManager.startMonitoring()

                    // 6. Register daemon via SMAppService (LaunchAgent) and wait for reachability.
                    //    Once the daemon creates ~/.arcbox/run/docker.sock, the /var/run/docker.sock
                    //    symlink created in step 2 becomes active automatically.
                    await daemonManager.enableDaemon()

                    // 7. Initialize gRPC / Docker clients.
                    initClientsIfNeeded()

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

    private func setupHelper() async {
        do {
            try await helperManager.register()
        } catch HelperError.requiresApproval {
            // User previously denied in System Settings.
            // Show a non-blocking UI banner; core features still work.
            appVM.showHelperApprovalBanner = true
            return
        } catch {
            return
        }

        let socketPath = DaemonManager.dockerSocketPath   // ~/.arcbox/run/docker.sock
        let bundlePath = Bundle.main.bundleURL.path

        // Each operation is independent — await separately so that one failure
        // (e.g. socket occupied by OrbStack) does not cancel the other two.
        try? await helperManager.setupDockerSocket(socketPath: socketPath)
        try? await helperManager.installCLITools(appBundlePath: bundlePath)
        try? await helperManager.setupDNSResolver()
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
