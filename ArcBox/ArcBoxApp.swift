import AppKit
import ArcBoxClient
import DockerClient
import OSLog
@preconcurrency import Sentry
import Sparkle
import SwiftUI

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?
    var eventMonitor: DockerEventMonitor?
    var startupOrchestrator: StartupOrchestrator?

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
    @State private var startupOrchestrator: StartupOrchestrator?

    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        Self.initSentry()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    /// Initialize Sentry crash reporting if a DSN is configured.
    /// DSN is read from Info.plist (injected via SENTRY_DSN build setting).
    /// No-ops gracefully when DSN is empty or placeholder.
    private static func initSentry() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
              !dsn.isEmpty, dsn != "YOUR_SENTRY_DSN_HERE", dsn != "$(SENTRY_DSN)"
        else {
            Log.startup.info("Sentry DSN not configured, crash reporting disabled")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.enableAutoSessionTracking = true
            options.enableCrashHandler = true
            options.enableAutoPerformanceTracing = true
            options.tracesSampleRate = 0.2
            options.beforeSend = { event in
                // Scrub PII: remove user paths from breadcrumbs and exceptions.
                Self.scrubPII(event)
                return event
            }
            #if DEBUG
            options.debug = true
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        SentrySDK.configureScope { scope in
            scope.setTag(value: "app", key: "process_type")
            scope.setTag(value: version, key: "app_version")
        }
        Log.startup.info("Sentry initialized")
    }

    /// Strip home directory paths from Sentry events to avoid leaking usernames.
    private static func scrubPII(_ event: Event) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        guard !homeDir.isEmpty else { return }
        for breadcrumb in event.breadcrumbs ?? [] {
            if let msg = breadcrumb.message {
                breadcrumb.message = msg.replacingOccurrences(of: homeDir, with: "~")
            }
        }
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
                    appDelegate.eventMonitor = eventMonitor

                    let orchestrator = StartupOrchestrator(
                        bootAssetManager: bootAssetManager,
                        daemonManager: daemonManager,
                        dockerToolSetupManager: dockerToolSetupManager,
                        onClientsNeeded: { try initClientsIfNeeded() }
                    )
                    startupOrchestrator = orchestrator
                    appDelegate.startupOrchestrator = orchestrator
                    await orchestrator.start()

                    Task {
                        try? await Task.sleep(for: StartupConstants.updateCheckDelay)
                        await bootAssetManager.checkForUpdates()
                    }
                }
                // Re-create clients whenever daemon transitions to running
                // (covers the case where monitoring detects the daemon after
                // the initial .task check has already passed).
                // When login item approval is revoked and then re-granted,
                // re-run helper setup and restart the daemon.
                .onChange(of: daemonManager.state) { _, newState in
                    if newState.isRunning {
                        try? initClientsIfNeeded()
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

    private func initClientsIfNeeded() throws {
        guard daemonManager.state.isRunning else { return }

        if dockerClient == nil {
            dockerClient = DockerClient()
        }

        if arcboxClient == nil {
            let client = try ArcBoxClient()
            Task { try await client.runConnections() }
            arcboxClient = client
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
