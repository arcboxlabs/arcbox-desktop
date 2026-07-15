import ArcBoxAuth
import ArcBoxClient
import DockerClient
import FleetPlatformClient
import Foundation
import OSLog
import Sparkle
import SwiftUI

@main
struct ArcBoxDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    // Lightweight init — no network calls until view appears
    @State private var appVM = AppViewModel()
    // Lightweight init — no network calls until view appears
    @State private var daemonManager = DaemonManager()
    // Lightweight init — Keychain restoration starts from the scene task
    @State private var authSession = AuthSession()
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient?
    @State private var fleetAgentConnection = FleetAgentConnection()
    @State private var fleetPlatformClient: FleetPlatformClient?
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
    // Lightweight init — no network calls until view appears
    @State private var systemVmBackendVM = SystemVmBackendModel()
    // App-scoped so the Fleet Watch survives closing the main window.
    @State private var runnersVM = RunnersViewModel()

    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController

    init() {
        Self.initSentry()
        Self.initPostHog()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        Window("ArcBox", id: "main") {
            ContentView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(networksVM)
                .environment(volumesVM)
                .environment(authSession)
                .environment(runnersVM)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.fleetControlClient, fleetAgentConnection.controlClient)
                .environment(\.fleetPlatformClient, fleetPlatformClient)
                .environment(\.startupOrchestrator, startupOrchestrator)
                .environment(\.accessTokenProvider, authSession)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    appDelegate.deepLinkRouter.configure(
                        .init(
                            appVM: appVM,
                            containersVM: containersVM,
                            volumesVM: volumesVM,
                            imagesVM: imagesVM,
                            networksVM: networksVM,
                            openMainWindow: { openWindow(id: "main") },
                            openSettingsWindow: { openWindow(id: "settings") },
                            oauthCallbackScheme: OIDCClientConfiguration.redirectURI.scheme,
                            onOAuthCallback: { url in
                                Task { await authSession.handleAuthorizationCallback(url) }
                            }
                        ))
                    fleetAgentConnection.start()
                    appDelegate.fleetAgentConnection = fleetAgentConnection
                    appDelegate.runnersVM = runnersVM
                    Task {
                        await authSession.restoreSession()
                        initFleetPlatformClientIfNeeded()
                        runnersVM.start(
                            controlClient: fleetAgentConnection.controlClient,
                            platformClient: fleetPlatformClient,
                            authentication: authSession,
                            agentReadiness: fleetAgentConnection
                        )
                        await authSession.loadUserInfo()
                    }
                    Task {
                        do {
                            _ = try await fleetAgentConnection.ensureReady()
                        } catch is CancellationError {
                            Log.fleet.info("Fleet Agent readiness probe cancelled")
                        } catch {
                            Log.fleet.info(
                                "Fleet Agent is not ready: \(error.localizedDescription, privacy: .private)"
                            )
                        }
                    }

                    guard startupOrchestrator == nil else { return }

                    appDelegate.daemonManager = daemonManager
                    appDelegate.eventMonitor = eventMonitor

                    let startupStart = CFAbsoluteTimeGetCurrent()
                    let orchestrator = StartupOrchestrator(
                        daemonManager: daemonManager,
                        onClientsNeeded: { try initClientsAndReturn() }
                    )
                    startupOrchestrator = orchestrator
                    appDelegate.startupOrchestrator = orchestrator
                    await orchestrator.start()

                    // Bridge startup result to PostHog analytics.
                    let startupMs = Int((CFAbsoluteTimeGetCurrent() - startupStart) * 1000)
                    if orchestrator.isReady {
                        Analytics.capture(
                            .startupCompleted,
                            properties: [
                                "duration_ms": startupMs
                            ])
                    } else if case .failed(let step, _) = orchestrator.phase {
                        Analytics.capture(
                            .startupFailed,
                            properties: [
                                "duration_ms": startupMs,
                                "step": step.label,
                            ])
                    }
                }
                // DockerClient is created when daemon state becomes running.
                // ListViews gate their initial load on setupPhase.isDockerReady
                // (reported via the gRPC WatchSetupStatus stream) to avoid hitting the
                // Docker API before the daemon has finished initialization.
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
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appInfo) {
                Button("About ArcBox") {
                    showAboutWindow()
                }
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .appSettings) {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Label("Settings...", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(authSession)
                .environment(systemVmBackendVM)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.accessTokenProvider, authSession)
                .environment(\.fleetControlClient, fleetAgentConnection.controlClient)
                .environment(\.fleetPlatformClient, fleetPlatformClient)
        }
        .defaultSize(width: 700, height: 580)
        .windowResizability(.contentSize)

        MenuBarExtra("ArcBox", systemImage: "shippingbox", isInserted: $showInMenuBar) {
            MenuBarView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(networksVM)
                .environment(volumesVM)
                .environment(authSession)
                .environment(runnersVM)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.fleetControlClient, fleetAgentConnection.controlClient)
                .environment(\.fleetPlatformClient, fleetPlatformClient)
                .environment(\.startupOrchestrator, startupOrchestrator)
                .environment(\.accessTokenProvider, authSession)
        }
        .menuBarExtraStyle(.window)
    }

    /// Create gRPC client and return it for the orchestrator.
    /// DockerClient is created separately in onChange(of: daemonManager.state).
    /// ListViews gate data loading on setupPhase.isDockerReady.
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

    /// Create the authenticated Platform REST client without starting network work.
    private func initFleetPlatformClientIfNeeded() {
        guard fleetPlatformClient == nil else { return }

        let configuration = FleetPlatformConfiguration.current
        Log.fleet.info(
            "Creating FleetPlatformClient for \(configuration.baseURL.absoluteString, privacy: .public)"
        )
        fleetPlatformClient = FleetPlatformClient(
            configuration: configuration,
            accessTokenProvider: authSession
        )
    }
}
