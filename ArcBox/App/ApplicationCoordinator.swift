import AppKit
import ArcBoxAuth
import ArcBoxClient
import DockerClient
import FleetPlatformClient
import Foundation
import OSLog
import Observation
import Sparkle
import SwiftUI

@MainActor
final class ApplicationCoordinator: NSObject {
    let appVM = AppViewModel()
    let daemonManager = DaemonManager()
    let authSession = AuthSession()
    let containersVM = ContainersViewModel()
    let imagesVM = ImagesViewModel()
    let networksVM = NetworksViewModel()
    let volumesVM = VolumesViewModel()
    let systemVmBackendVM = SystemVmBackendModel()
    // App-scoped so the Fleet Watch survives closing the main window.
    let runnersVM = RunnersViewModel()

    private let eventMonitor = DockerEventMonitor()
    private let sandboxEventMonitor = SandboxEventMonitor()
    private let machineEventMonitor = MachineEventMonitor()
    private let sleepWakeManager = SleepWakeManager()
    private let deepLinkRouter = DeepLinkRouter()
    private let fleetAgentConnection = FleetAgentConnection()
    private lazy var notifications = NotificationCoordinator(
        isUserWatching: { [weak self] in self?.isUserWatching($0) ?? false },
        openDestination: { [weak self] in self?.deepLinkRouter.handle($0) },
        isDaemonRunning: { [weak self] in self?.daemonManager.state.isRunning ?? false }
    )
    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController
    private let updaterSettings: UpdaterSettingsModel
    private var fleetPlatformClient: FleetPlatformClient?

    private(set) var arcboxClient: ArcBoxClient?
    private(set) var dockerClient: DockerClient?
    private(set) var startupOrchestrator: StartupOrchestrator?

    private var mainWindowController: MainWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var gettingStartedWindowController: OnboardingWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?
    private var quitWindowController: QuitWindowController?
    private var mainHost: NSHostingController<AnyView>?
    private var settingsHost: NSHostingController<AnyView>?
    private var menuBarHost: NSHostingController<AnyView>?
    private var startupTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var lastDaemonState: DaemonState?
    /// The identity currently mirrored into PostHog, so re-identify only runs
    /// when it actually changes — `loadUserInfo()` enriches it after sign-in.
    private var identifiedAs: AuthIdentity?
    /// Whether PostHog currently holds an identity, tracked across launches so
    /// a reset owed from a previous run is not missed.  Bookkeeping, not a user
    /// preference, so it stays out of `AppPreferences`.
    private static let analyticsIdentifiedKey = "analyticsIdentified"
    private var lastShowInMenuBar: Bool
    private var lastUpdateChannel: String
    private var lastTelemetryEnabled: Bool
    private var isOnboarding: Bool
    private var deepLinksConfigured = false
    private var started = false
    private(set) var isTerminating = false

    override init() {
        let hasCompletedOnboarding = AppPreferences.hasCompletedOnboarding()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        updaterSettings = UpdaterSettingsModel(updater: updaterController.updater)
        lastShowInMenuBar = UserDefaults.standard.bool(forKey: "showInMenuBar")
        lastUpdateChannel = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        lastTelemetryEnabled = UserDefaults.standard.bool(forKey: "telemetryEnabled")
        isOnboarding = !hasCompletedOnboarding
        super.init()
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var canUseMainInterface: Bool {
        !isTerminating && !isOnboarding
    }

    func start() {
        guard !started else { return }
        started = true

        let orchestrator = StartupOrchestrator(
            daemonManager: daemonManager,
            onClientsNeeded: { [unowned self] in try initClientsAndReturn() }
        )
        startupOrchestrator = orchestrator
        observeStartupPhase()

        installWindows()
        if !isOnboarding {
            configureDeepLinks()
        }
        observeDaemonState()
        observeAuthIdentity()
        configureNotifications()
        _ = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.defaultsDidChange()
            }
        }

        fleetAgentConnection.start()
        Task { [weak self] in
            guard let self else { return }
            await authSession.restoreSession()
            initFleetPlatformClientIfNeeded()
            runnersVM.start(
                controlClient: fleetAgentConnection.controlClient,
                platformClient: fleetPlatformClient,
                authentication: authSession,
                agentReadiness: fleetAgentConnection
            )
            await authSession.refreshSession()
        }
        Task { [weak self] in
            guard let self else { return }
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

        if !isOnboarding {
            startRuntimeIfNeeded()
        }
    }

    func handleDeepLink(_ url: URL) {
        guard !isTerminating else { return }
        deepLinkRouter.handle(url)
    }

    func showMainWindow() {
        guard !isTerminating else { return }
        guard !isOnboarding else {
            showOnboarding()
            return
        }
        activate()
        mainWindowController?.window?.deminiaturize(nil)
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func showSettings(tab: SettingsTab? = nil) {
        guard !isTerminating else { return }
        guard !isOnboarding else {
            showOnboarding()
            return
        }
        if let tab {
            appVM.settingsTab = tab
        }
        Analytics.capture(.settingsOpened, properties: ["tab": appVM.settingsTab?.rawValue ?? "none"])
        if settingsWindowController == nil {
            let screen =
                NSApp.keyWindow?.screen
                ?? NSApp.mainWindow?.screen
                ?? mainWindowController?.window?.screen
                ?? NSScreen.main
            let host = NSHostingController(rootView: makeSettingsRoot())
            host.sceneBridgingOptions = .all
            settingsHost = host
            settingsWindowController = SettingsWindowController(
                contentViewController: host,
                screen: screen
            )
        }
        activate()
        settingsWindowController?.window?.deminiaturize(nil)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        guard !isTerminating else { return }
        activate()
        showAboutWindow()
    }

    func showGettingStarted() {
        guard canUseMainInterface, let orchestrator = startupOrchestrator else { return }

        if gettingStartedWindowController?.window?.isVisible != true {
            let host = NSHostingController(
                rootView: OnboardingView(
                    orchestrator: orchestrator,
                    initialStep: .welcome,
                    isReplay: true,
                    onStart: {},
                    onComplete: { [weak self] in
                        self?.gettingStartedWindowController?.window?.performClose(nil)
                    },
                    onQuit: {}
                ))
            gettingStartedWindowController = OnboardingWindowController(
                title: "Getting Started with ArcBox",
                contentViewController: host,
                allowsClosing: true,
                onClose: {}
            )
        }

        activate()
        gettingStartedWindowController?.show()
    }

    func checkForUpdates() {
        guard !isTerminating else { return }
        updaterController.updater.checkForUpdates()
    }

    @discardableResult
    func beginTermination() -> Bool {
        guard !isTerminating else { return false }
        isTerminating = true

        notifications.stop()
        authSession.cancelSignIn()
        statusItemController?.closePopover()
        statusItemController?.setVisible(false)
        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main

        if NSApp.modalWindow != nil {
            NSApp.abortModal()
        }
        for window in NSApp.windows {
            window.orderOut(nil)
        }

        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = nil
        NSApp.windowsMenu = nil
        let controller = QuitWindowController(screen: screen)
        quitWindowController = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func requestQuit() {
        NSApp.terminate(nil)
    }

    func shutdown() async {
        let enrollmentSettled = await runnersVM.prepareForTermination()
        if !enrollmentSettled {
            Log.fleet.warning(
                "Fleet enrollment did not settle before the application termination deadline"
            )
        }
        let connectionClosedGracefully = await fleetAgentConnection.shutdown()
        if !connectionClosedGracefully {
            Log.fleet.warning(
                "Fleet client transport required forced shutdown during application termination"
            )
        }

        startupTask?.cancel()
        await startupOrchestrator?.cancelForTermination()
        await startupTask?.value
        startupTask = nil
        eventMonitor.stop()
        sandboxEventMonitor.stop()
        machineEventMonitor.stop()
        sleepWakeManager.stop()
        await updateDockerContext(useArcBox: false).value
        arcboxClient?.close()
        connectionTask?.cancel()
        connectionTask = nil
        daemonManager.stopWatching()
        await daemonManager.disableDaemon()
    }

    private func installWindows() {
        let mainHost = NSHostingController(rootView: makeMainRoot())
        mainHost.sceneBridgingOptions = .all
        let menuBarHost = NSHostingController(rootView: makeMenuBarRoot())

        self.mainHost = mainHost
        self.menuBarHost = menuBarHost
        mainWindowController = MainWindowController(contentViewController: mainHost)
        statusItemController = StatusItemController(contentViewController: menuBarHost)
        statusItemController?.setVisible(!isOnboarding && lastShowInMenuBar)
    }

    private func configureDeepLinks() {
        guard !deepLinksConfigured else { return }
        deepLinksConfigured = true
        deepLinkRouter.configure(
            .init(
                appVM: appVM,
                openMainWindow: { [weak self] in self?.showMainWindow() },
                openSettingsWindow: { [weak self] in self?.showSettings() }
            ))
    }

    private func configureNotifications() {
        sandboxEventMonitor.onEvent = { [weak self] event in
            self?.notifications.handleSandboxEvent(event)
        }
        eventMonitor.onEvent = { [weak self] event in
            self?.notifications.handleDockerEvent(event)
        }
        notifications.start()
    }

    /// Whether what a notification would announce is already on screen. A
    /// closed or backgrounded window means the user is not watching, whatever
    /// the last selected section was.
    private func isUserWatching(_ destination: DeepLink) -> Bool {
        guard NSApp.isActive, mainWindowController?.window?.isVisible == true else { return false }
        switch destination {
        case .main, .settings:
            return true
        case .section(let item, _):
            return appVM.currentNav == item
        }
    }

    private func startRuntimeIfNeeded(allowingAdministratorPrompt: Bool = false) {
        guard !isTerminating, startupTask == nil, let orchestrator = startupOrchestrator else {
            return
        }

        startupTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = CFAbsoluteTimeGetCurrent()
            await orchestrator.start(
                allowingAdministratorPrompt: allowingAdministratorPrompt
            )
            captureStartupResult(orchestrator, startedAt: startedAt)
            startupTask = nil
        }
    }

    private func showOnboarding(startingAt initialStep: OnboardingStep? = nil) {
        guard !isTerminating, let orchestrator = startupOrchestrator else { return }

        let screen =
            NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? mainWindowController?.window?.screen
            ?? NSScreen.main
        isOnboarding = true
        mainWindowController?.window?.orderOut(nil)
        settingsWindowController?.window?.orderOut(nil)
        gettingStartedWindowController?.window?.orderOut(nil)
        gettingStartedWindowController = nil
        statusItemController?.setVisible(false)

        if onboardingWindowController == nil {
            let host = NSHostingController(
                rootView: OnboardingView(
                    orchestrator: orchestrator,
                    initialStep: initialStep ?? .welcome,
                    onStart: { [weak self] in
                        self?.startRuntimeIfNeeded(allowingAdministratorPrompt: true)
                    },
                    onComplete: { [weak self] in
                        self?.completeOnboarding()
                    },
                    onQuit: { [weak self] in
                        self?.requestQuit()
                    }
                ))
            onboardingWindowController = OnboardingWindowController(
                contentViewController: host,
                screen: screen,
                onClose: { [weak self] in
                    self?.requestQuit()
                }
            )
        }

        activate()
        onboardingWindowController?.show()
    }

    private func completeOnboarding() {
        guard !isTerminating, startupOrchestrator?.isRuntimeReady == true else { return }

        AppPreferences.markOnboardingCompleted()
        isOnboarding = false
        onboardingWindowController?.window?.orderOut(nil)
        onboardingWindowController = nil

        statusItemController?.setVisible(lastShowInMenuBar)
        showMainWindow()
        configureDeepLinks()
    }

    private func observeStartupPhase() {
        guard let orchestrator = startupOrchestrator else { return }
        withObservationTracking {
            _ = orchestrator.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.startupPhaseDidChange()
            }
        }
    }

    private func startupPhaseDidChange() {
        guard !isTerminating else { return }
        observeStartupPhase()
        guard startupOrchestrator?.phase == .requiresAdministratorApproval else { return }
        showOnboarding(startingAt: .permission)
    }

    private func observeDaemonState() {
        lastDaemonState = daemonManager.state
        trackDaemonState()
    }

    private func observeAuthIdentity() {
        syncAnalyticsIdentity()
        trackAuthIdentity()
    }

    private func trackAuthIdentity() {
        withObservationTracking {
            _ = authSession.status
            _ = authSession.identity
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.authIdentityDidChange()
            }
        }
    }

    private func authIdentityDidChange() {
        guard !isTerminating else { return }
        trackAuthIdentity()
        syncAnalyticsIdentity()
    }

    /// Mirrors platform sign-in state into PostHog: identify while signed in,
    /// reset on sign-out so the next account starts from a fresh anonymous ID.
    private func syncAnalyticsIdentity() {
        let identity = authSession.status == .signedIn ? authSession.identity : nil

        guard let identity else {
            identifiedAs = nil
            // The in-process cache cannot answer this on a signed-out launch:
            // the session may have ended while the app was closed (revoked
            // refresh token, cleared Keychain), leaving PostHog identified from
            // a previous run.  `analyticsIdentified` outlives the process, so
            // it is what decides whether a reset is still owed.
            guard UserDefaults.standard.bool(forKey: Self.analyticsIdentifiedKey) else { return }
            UserDefaults.standard.set(false, forKey: Self.analyticsIdentifiedKey)
            Analytics.reset()
            return
        }

        guard identity != identifiedAs else { return }
        identifiedAs = identity
        // Built with `if let` rather than optional subscripts: assigning a
        // `String?` into `[String: Any]` boxes the Optional itself.
        var properties: [String: Any] = [:]
        if let email = identity.email { properties["email"] = email }
        if let name = identity.name { properties["name"] = name }
        if let emailVerified = identity.emailVerified { properties["email_verified"] = emailVerified }
        UserDefaults.standard.set(true, forKey: Self.analyticsIdentifiedKey)
        Analytics.identify(identity.subject, properties: properties)
    }

    private func trackDaemonState() {
        withObservationTracking {
            _ = daemonManager.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.daemonStateDidChange()
            }
        }
    }

    private func daemonStateDidChange() {
        guard !isTerminating else { return }
        trackDaemonState()
        let state = daemonManager.state
        guard state != lastDaemonState else { return }
        let previousState = lastDaemonState
        lastDaemonState = state

        notifications.handleDaemonState(from: previousState, to: state)

        if state.isRunning {
            if dockerClient == nil {
                dockerClient = DockerClient()
                refreshHostedRoots()
            }
            if let dockerClient {
                eventMonitor.start(docker: dockerClient)
                sleepWakeManager.dockerClientRef = dockerClient
                sleepWakeManager.start()
            }
            if let arcboxClient {
                sandboxEventMonitor.start(client: arcboxClient, machineID: "default")
                machineEventMonitor.start(client: arcboxClient)
            }
            if UserDefaults.standard.bool(forKey: "switchDockerContextAutomatically") {
                updateDockerContext(useArcBox: true)
            }
        } else {
            eventMonitor.stop()
            sandboxEventMonitor.stop()
            machineEventMonitor.stop()
            sleepWakeManager.stop()
            notifications.runtimeStopped()
            updateDockerContext(useArcBox: false)
        }
    }

    @discardableResult
    private func updateDockerContext(useArcBox: Bool) -> Task<Void, Never> {
        DockerContextManager.update(useArcBox: useArcBox) { [self] result in
            switch result {
            case .success:
                if let retry = self.appVM.dockerContextRetry, case .preference = retry {
                    return
                }
                appVM.dockerContextError = nil
                appVM.dockerContextRetry = nil
            case let .failure(error):
                Log.context.error(
                    "Failed to update Docker context: \(error.localizedDescription, privacy: .public)"
                )
                if let retry = self.appVM.dockerContextRetry, case .preference = retry {
                    return
                }
                appVM.dockerContextError =
                    "The Docker context was not updated: \(error.localizedDescription) "
                    + "Check that the Docker CLI is installed and ~/.docker/config.json is writable, then try again."
                appVM.dockerContextRetry = .lifecycle(useArcBox: useArcBox)
            }
        }
    }

    private func initClientsAndReturn() throws -> ArcBoxClient {
        if let arcboxClient {
            Log.startup.info("Reusing existing ArcBoxClient")
            return arcboxClient
        }

        connectionTask?.cancel()
        let client = try ArcBoxClient()
        connectionTask = Task {
            do {
                Log.startup.info("runConnections starting")
                try await client.runConnections()
                Log.startup.info("runConnections ended")
            } catch {
                Log.startup.error(
                    "runConnections failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        arcboxClient = client
        refreshHostedRoots()
        return client
    }

    private func refreshHostedRoots() {
        mainHost?.rootView = makeMainRoot()
        settingsHost?.rootView = makeSettingsRoot()
        menuBarHost?.rootView = makeMenuBarRoot()
    }

    private func makeMainRoot() -> AnyView {
        return AnyView(
            ContentView { [weak self] in
                self?.accountButtonPressed()
            }
            .environment(appVM)
            .environment(daemonManager)
            .environment(containersVM)
            .environment(imagesVM)
            .environment(networksVM)
            .environment(volumesVM)
            .environment(sandboxEventMonitor)
            .environment(authSession)
            .environment(runnersVM)
            .environment(\.arcboxClient, arcboxClient)
            .environment(\.dockerClient, dockerClient)
            .environment(\.startupOrchestrator, startupOrchestrator)
            .environment(\.accessTokenProvider, authSession)
            .frame(minWidth: 900, minHeight: 600)
        )
    }

    private func makeSettingsRoot() -> AnyView {
        AnyView(
            SettingsView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(authSession)
                .environment(systemVmBackendVM)
                .environment(updaterSettings)
                .environment(runnersVM.fleet)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.accessTokenProvider, authSession)
        )
    }

    private func makeMenuBarRoot() -> AnyView {
        AnyView(
            MenuBarView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(containersVM)
                .environment(imagesVM)
                .environment(networksVM)
                .environment(volumesVM)
                .environment(authSession)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .environment(\.startupOrchestrator, startupOrchestrator)
                .environment(\.accessTokenProvider, authSession)
        )
    }

    private func accountButtonPressed() {
        guard !isTerminating else { return }
        if authSession.status == .signedIn {
            showSettings(tab: .account)
            return
        }
        guard authSession.status != .restoring, authSession.status != .signingIn,
            !authSession.configuration.isPlaceholder
        else { return }
        Task {
            await authSession.signIn()
        }
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

    private func activate() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureStartupResult(
        _ orchestrator: StartupOrchestrator,
        startedAt: CFAbsoluteTime
    ) {
        let duration = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        if orchestrator.isReady {
            Analytics.capture(
                .startupCompleted,
                properties: ["duration_ms": duration]
            )
        } else if case .failed(let step, _) = orchestrator.phase {
            Analytics.capture(
                .startupFailed,
                properties: [
                    "duration_ms": duration,
                    "step": step.label,
                ]
            )
        }
    }

    private func defaultsDidChange() {
        guard !isTerminating else { return }
        let defaults = UserDefaults.standard
        let showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        if showInMenuBar != lastShowInMenuBar {
            lastShowInMenuBar = showInMenuBar
            statusItemController?.setVisible(!isOnboarding && showInMenuBar)
        }

        let updateChannel = defaults.string(forKey: "updateChannel") ?? "stable"
        if updateChannel != lastUpdateChannel {
            lastUpdateChannel = updateChannel
            updaterController.updater.resetUpdateCycle()
            Analytics.register(["update_channel": updateChannel])
        }

        let telemetryEnabled = defaults.bool(forKey: "telemetryEnabled")
        if telemetryEnabled != lastTelemetryEnabled {
            lastTelemetryEnabled = telemetryEnabled
            telemetryPreferenceDidChange(enabled: telemetryEnabled)
        }
    }

    /// Applies the Privacy toggle.  Opting back in has to re-run identify:
    /// the SDK drops `identify` while opted out, so a user who signs in first
    /// and enables telemetry afterwards would otherwise stay anonymous.
    private func telemetryPreferenceDidChange(enabled: Bool) {
        #if DEBUG
            // Development builds never send telemetry; see `initPostHog`.
            return
        #else
            if enabled {
                Analytics.optIn()
                identifiedAs = nil
                syncAnalyticsIdentity()
            } else {
                Analytics.optOut()
            }
        #endif
    }
}
