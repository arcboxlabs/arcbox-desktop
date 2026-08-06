import AppKit
import ArcBoxAuth
import ArcBoxClient
import DockerClient
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

    private let eventMonitor = DockerEventMonitor()
    private let sandboxEventMonitor = SandboxEventMonitor()
    private let machineEventMonitor = MachineEventMonitor()
    private let sleepWakeManager = SleepWakeManager()
    private let deepLinkRouter = DeepLinkRouter()
    private let notifications = UserNotificationService()
    private var sandboxNotificationRules = SandboxNotificationRules()
    private let updaterDelegate = UpdaterDelegate()
    private let updaterController: SPUStandardUpdaterController
    private let updaterSettings: UpdaterSettingsModel

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
    private var lastShowInMenuBar: Bool
    private var lastUpdateChannel: String
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

        Task { [weak self] in
            await self?.authSession.loadUserInfo()
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

        WebAuthenticationController.shared.cancelForTermination()
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
        startupTask?.cancel()
        await startupOrchestrator?.cancelForTermination()
        await startupTask?.value
        startupTask = nil
        eventMonitor.stop()
        sandboxEventMonitor.stop()
        machineEventMonitor.stop()
        sleepWakeManager.stop()
        DockerContextManager.restorePreviousContext()
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
                containersVM: containersVM,
                volumesVM: volumesVM,
                imagesVM: imagesVM,
                networksVM: networksVM,
                openMainWindow: { [weak self] in self?.showMainWindow() },
                openSettingsWindow: { [weak self] in self?.showSettings() },
                oauthCallbackScheme: OIDCClientConfiguration.redirectURI.scheme,
                onOAuthCallback: { [weak self] url in
                    Task { await self?.authSession.handleAuthorizationCallback(url) }
                }
            ))
    }

    private func configureNotifications() {
        notifications.isUserWatching = { [weak self] destination in
            self?.isUserWatching(destination) ?? false
        }
        notifications.openDestination = { [weak self] destination in
            self?.deepLinkRouter.handle(destination)
        }
        sandboxEventMonitor.onEvent = { [weak self] event in
            guard let self, let notification = sandboxNotificationRules.notification(for: event) else {
                return
            }
            notifications.post(notification)
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
        guard !isTerminating, startupOrchestrator?.isReady == true else { return }

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

        if let notification = DaemonNotificationRules.notification(from: previousState, to: state) {
            notifications.post(notification)
        }

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
            DockerContextManager.switchToArcBox()
        } else {
            eventMonitor.stop()
            sandboxEventMonitor.stop()
            machineEventMonitor.stop()
            sleepWakeManager.stop()
            DockerContextManager.restorePreviousContext()
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
        guard authSession.status != .signingIn, !authSession.configuration.isPlaceholder else {
            return
        }
        Task {
            await authSession.signIn(using: WebAuthenticationController.shared.authenticate)
        }
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
        }
    }
}
