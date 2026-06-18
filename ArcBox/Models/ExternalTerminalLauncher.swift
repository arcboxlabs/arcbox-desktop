import AppKit
import Darwin
import os

/// Launches an external terminal app with Docker environment pre-configured.
enum ExternalTerminalLauncher {
    private static let logger = Log.terminal

    private enum TerminalApp: Sendable {
        case terminal
        case iTerm

        var bundleIdentifier: String {
            switch self {
            case .terminal: "com.apple.Terminal"
            case .iTerm: "com.googlecode.iterm2"
            }
        }
    }

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
        let command = makeCommand(containerID: containerID, shell: shell)
        let script = makeCommandScript(command: command)
        guard let scriptURL = writeCommandScript(script) else { return }

        openCommandScript(
            scriptURL,
            terminal: resolveTerminal(preference: preference),
            fallbackCommand: command
        )
    }

    private static func resolveTerminal(preference: String) -> TerminalApp {
        switch preference {
        case "iterm":
            .iTerm
        case "terminal":
            .terminal
        default:
            isITermInstalled() ? .iTerm : .terminal
        }
    }

    private static func makeCommand(containerID: String?, shell: String) -> String {
        let dockerHostExport = "export DOCKER_HOST=\(shellEscape(dockerHost))"
        guard let dockerPath = DockerCLIResolver.findDockerCLI() else {
            return [
                dockerHostExport,
                "printf '\\nArcBox: Docker CLI not found. Install Docker CLI or make it available at /opt/homebrew/bin/docker or /usr/local/bin/docker.\\n'",
                "arcbox_status=127",
            ].joined(separator: "\n")
        }

        guard let containerID else {
            return [
                dockerHostExport,
                "printf 'ArcBox Docker host configured: %s\\n' \"$DOCKER_HOST\"",
                "\"${SHELL:-/bin/zsh}\" -l",
                "arcbox_status=$?",
            ].joined(separator: "\n")
        }

        return [
            dockerHostExport,
            "\(shellEscape(dockerPath)) exec -it \(shellEscape(containerID)) \(shellEscape(shell))",
            "arcbox_status=$?",
            "if [ \"$arcbox_status\" -ne 0 ]; then printf '\\nArcBox: docker exec failed with exit code %s. Check that the container is running and that the selected shell exists.\\n' \"$arcbox_status\"; fi",
        ].joined(separator: "\n")
    }

    private static func makeCommandScript(command: String) -> String {
        [
            "#!/bin/zsh",
            "arcbox_script_path=\"$0\"",
            "trap 'rm -f \"$arcbox_script_path\"' EXIT",
            command,
            "if [ \"${arcbox_status:-0}\" -ne 0 ]; then printf '\\nPress return to close this window. '; read -r _; fi",
            "exit \"${arcbox_status:-0}\"",
        ].joined(separator: "\n")
    }

    private static func writeCommandScript(_ source: String) -> URL? {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("arcbox-terminal-\(UUID().uuidString).command")

        do {
            try source.write(to: scriptURL, atomically: true, encoding: .utf8)
            chmod(scriptURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            return scriptURL
        } catch {
            logger.error("Failed to write external terminal command: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func openCommandScript(_ scriptURL: URL, terminal: TerminalApp, fallbackCommand: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleIdentifier) else {
            NSWorkspace.shared.open(scriptURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([scriptURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in
                logger.error("Failed to open command script: \(error.localizedDescription, privacy: .public)")
                openWithAppleScript(terminal: terminal, command: fallbackCommand)
            }
        }
    }

    private static func openWithAppleScript(terminal: TerminalApp, command: String) {
        switch terminal {
        case .terminal:
            openTerminalApp(command: command)
        case .iTerm:
            openITerm(command: command)
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
                await MainActor.run { logger.error("Failed to create AppleScript") }
                return
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                let errorMessage = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
                await MainActor.run { logger.error("AppleScript error: \(errorMessage, privacy: .public)") }
            }
        }
    }
}
