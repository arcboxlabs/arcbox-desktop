import AppKit
import ArcBoxClient
import DockerClient
import Foundation

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
