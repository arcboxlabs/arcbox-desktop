import AppKit

/// Launches an external terminal app with Docker environment pre-configured.
enum ExternalTerminalLauncher {
    private static let logger = Log.terminal

    /// The Docker socket environment variable value used by ArcBox.
    private static var dockerHost: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "unix://\(home)/.arcbox/run/docker.sock"
    }

    /// Open an external terminal with an optional docker exec command.
    /// - Parameters:
    ///   - preference: The user's terminal preference: "terminal", "iterm", or "lastUsed".
    ///   - containerID: Optional container ID to exec into.
    ///   - shell: Shell to use (e.g. "/bin/sh"). Only used when containerID is provided.
    static func open(preference: String, containerID: String? = nil, shell: String = "/bin/sh") {
        let command: String
        if let containerID {
            command = "export DOCKER_HOST=\(shellEscape(dockerHost)) && docker exec -it \(shellEscape(containerID)) \(shellEscape(shell))"
        } else {
            command = "export DOCKER_HOST=\(shellEscape(dockerHost))"
        }

        switch preference {
        case "iterm":
            openITerm(command: command)
        case "terminal":
            openTerminalApp(command: command)
        default: // "lastUsed" — try iTerm first, fall back to Terminal.app
            if isITermInstalled() {
                openITerm(command: command)
            } else {
                openTerminalApp(command: command)
            }
        }
    }

    // MARK: - Terminal.app

    private static func openTerminalApp(command: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapeForAppleScript(command))"
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - iTerm

    private static func openITerm(command: String) {
        let script = """
        tell application "iTerm"
            activate
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text "\(escapeForAppleScript(command))"
            end tell
        end tell
        """
        runAppleScript(script)
    }

    private static func isITermInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") != nil
    }

    // MARK: - Helpers

    /// Wrap a value in single quotes for safe shell interpolation.
    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
              .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) {
        let scriptSource = source
        Task.detached {
            guard let script = NSAppleScript(source: scriptSource) else {
                logger.error("Failed to create AppleScript")
                return
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                let errorMessage = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
                logger.error("AppleScript error: \(errorMessage, privacy: .public)")
            }
        }
    }
}
