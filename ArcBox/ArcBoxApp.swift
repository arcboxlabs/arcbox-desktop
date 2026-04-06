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
    var arcboxClient: ArcBoxClient?
    var connectionTask: Task<Void, Never>?
    /// Set to true when the user explicitly requests a full quit (e.g. from menu bar).
    var forceQuit = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let keepRunning = UserDefaults.standard.bool(forKey: "keepRunning")
        let showInMenuBar = UserDefaults.standard.bool(forKey: "showInMenuBar")

        // If "keep running" is enabled and menu bar is visible, hide the app instead of quitting
        // — unless the user explicitly chose Quit from the menu bar.
        if keepRunning && showInMenuBar && !forceQuit {
            for window in NSApp.windows where window.isVisible {
                window.close()
            }
            return .terminateCancel
        }

        eventMonitor?.stop()
        DockerContextManager.restorePreviousContext()
        arcboxClient?.close()
        connectionTask?.cancel()
        guard let daemonManager else { return .terminateNow }

        Task { @MainActor in
            daemonManager.stopWatching()
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
    // Lightweight init — no network calls until view appears
    @State private var appVM = AppViewModel()
    // Lightweight init — no network calls until view appears
    @State private var daemonManager = DaemonManager()
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient?
    // Lightweight init — no network calls until view appears
    @State private var eventMonitor = DockerEventMonitor()
    @State private var sleepWakeManager = SleepWakeManager()
    @State private var startupOrchestrator: StartupOrchestrator?
    @AppStorage("showInMenuBar") private var showInMenuBar = false
    @AppStorage("autoUpdate") private var autoUpdate = false
    @AppStorage("updateChannel") private var updateChannel = "stable"

    // Shared ViewModels used by both main window and menu bar
    // Lightweight init — no network calls until view appears
    @State private var containersVM = ContainersViewModel()
    // Lightweight init — no network calls until view appears
    @State private var imagesVM = ImagesViewModel()
    // Lightweight init — no network calls until view appears
    @State private var networksVM = NetworksViewModel()
    // Lightweight init — no network calls until view appears
    @State private var volumesVM = VolumesViewModel()

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
                .environment(containersVM)
                .environment(imagesVM)
                .environment(networksVM)
                .environment(volumesVM)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.startupOrchestrator, startupOrchestrator)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    guard startupOrchestrator == nil else { return }

                    appDelegate.daemonManager = daemonManager
                    appDelegate.eventMonitor = eventMonitor

                    let orchestrator = StartupOrchestrator(
                        daemonManager: daemonManager,
                        onClientsNeeded: { try initClientsAndReturn() }
                    )
                    startupOrchestrator = orchestrator
                    appDelegate.startupOrchestrator = orchestrator
                    await orchestrator.start()
                }
                // IMPORTANT: DockerClient MUST be created here — only after daemon is confirmed running.
                // All ListViews use .task(id: docker != nil) to trigger their initial data load.
                // Creating DockerClient earlier (e.g., in initClientsAndReturn) causes those tasks
                // to fire before the Docker socket is ready, resulting in empty lists. (ABXD-76 / #169)
                .onOpenURL { url in handleDeepLink(url) }
                .onChange(of: daemonManager.state) { _, newState in
                    if newState.isRunning {
                        if dockerClient == nil {
                            dockerClient = DockerClient()
                        }
                        if let dockerClient {
                            eventMonitor.start(docker: dockerClient)
                            sleepWakeManager.dockerClientRef = dockerClient
                            sleepWakeManager.start()
                        }
                        DockerContextManager.switchToArcBox()
                    } else {
                        eventMonitor.stop()
                        sleepWakeManager.stop()
                        DockerContextManager.restorePreviousContext()
                    }
                }
                .onAppear {
                    // Sync auto-update preference to Sparkle
                    updaterController.updater.automaticallyChecksForUpdates = autoUpdate
                }
                .onChange(of: autoUpdate) { _, newValue in
                    updaterController.updater.automaticallyChecksForUpdates = newValue
                }
                .onChange(of: updateChannel) { _, _ in
                    // Force Sparkle to re-fetch the feed URL (which reads updateChannel via UpdaterDelegate)
                    updaterController.updater.resetUpdateCycle()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsView()
                .environment(\.dockerClient, dockerClient)
        }

        MenuBarExtra("ArcBox", systemImage: "shippingbox", isInserted: $showInMenuBar) {
            MenuBarView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(networksVM)
                .environment(volumesVM)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.startupOrchestrator, startupOrchestrator)
        }
        .menuBarExtraStyle(.window)
    }

    /// Create gRPC client and return it for the orchestrator.
    /// WARNING: Do NOT create DockerClient here — it must be deferred to
    /// onChange(of: daemonManager.state) so that .task(id: docker != nil)
    /// in ListViews only fires after the daemon is confirmed running. (ABXD-76 / #169)
    private func initClientsAndReturn() throws -> ArcBoxClient {
        if let existing = arcboxClient {
            Log.startup.info("Reusing existing ArcBoxClient")
            return existing
        }

        // Close any previous client that wasn't cleaned up (e.g. after a failed startup).
        appDelegate.arcboxClient?.close()
        appDelegate.connectionTask?.cancel()

        Log.startup.info("Creating new ArcBoxClient at \(ArcBoxClient.defaultSocketPath, privacy: .public)")
        let client = try ArcBoxClient()
        let task = Task {
            do {
                Log.startup.info("runConnections starting")
                try await client.runConnections()
                Log.startup.info("runConnections ended")
            } catch {
                Log.startup.error("runConnections failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        arcboxClient = client
        appDelegate.arcboxClient = client
        appDelegate.connectionTask = task
        return client
    }

    /// Handle incoming `arcbox://` deep links.
    /// TODO(ABXD-62): Register URL scheme in Info.plist or project build settings
    /// (INFOPLIST_KEY_LSApplicationCategoryType / CFBundleURLTypes) once scheme routing is finalized.
    private func handleDeepLink(_ url: URL) {
        Log.startup.info("Received deep link: \(url.absoluteString, privacy: .private)")
        guard url.scheme == "arcbox" else {
            Log.startup.warning("Ignoring unrecognized URL scheme: \(url.scheme ?? "nil", privacy: .private)")
            return
        }
        // TODO(ABXD-62): Route deep link to appropriate view based on host/path.
        // e.g. arcbox://containers/<id>, arcbox://settings, etc.
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
