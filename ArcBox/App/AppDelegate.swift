import AppKit
import ArcBoxClient
import DockerClient
import Foundation
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?
    var eventMonitor: DockerEventMonitor?
    var startupOrchestrator: StartupOrchestrator?
    var arcboxClient: ArcBoxClient?
    var connectionTask: Task<Void, Never>?
    let deepLinkRouter = DeepLinkRouter()
    var fleetAgentConnection: FleetAgentConnection?
    var runnersVM: RunnersViewModel?
    /// Set to true when the user explicitly requests a full quit (e.g. from menu bar).
    var forceQuit = false

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            deepLinkRouter.handle(url)
        }
    }

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
        let runnersVM = runnersVM
        let fleetAgentConnection = fleetAgentConnection
        let daemonManager = daemonManager

        Task { @MainActor in
            let enrollmentSettled = await runnersVM?.prepareForTermination() ?? true
            if !enrollmentSettled {
                Log.fleet.warning(
                    "Fleet enrollment did not settle before the application termination deadline"
                )
            }

            let connectionClosedGracefully = await fleetAgentConnection?.shutdown() ?? true
            if !connectionClosedGracefully {
                Log.fleet.warning(
                    "Fleet client transport required forced shutdown during application termination"
                )
            }

            if let daemonManager {
                daemonManager.stopWatching()
                await daemonManager.disableDaemon()
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
