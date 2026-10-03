import AppKit
import Darwin
import Foundation
import os

nonisolated enum ExternalTerminalLaunchError: LocalizedError {
    case commandFile(String)
    case appUnavailable(String)
    case launchFailed(String, String)
    case automationDenied(String)
    case automationFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .commandFile(let detail):
            "ArcBox could not prepare the terminal command: \(detail) Check available disk space and try again."
        case .appUnavailable(let appName):
            "\(appName) is not available. Choose another terminal in Settings > General."
        case .launchFailed(let appName, let detail):
            "ArcBox could not open \(appName): \(detail) Confirm the app can open .command files, or choose another terminal in Settings > General."
        case .automationDenied(let appName):
            "Automation access was denied. Open System Settings > Privacy & Security > Automation and allow ArcBox to control \(appName), then try again."
        case .automationFailed(let appName, let detail):
            "ArcBox could not control \(appName): \(detail) Check Automation access in System Settings > Privacy & Security, then try again."
        }
    }
}

/// Launches an external terminal app with Docker environment pre-configured.
enum ExternalTerminalLauncher {
    private static let logger = Log.terminal

    /// The Docker socket environment variable value used by ArcBox.
    private static var dockerHost: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDir = profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        return "unix://\(home)/\(dataDir)/run/docker.sock"
    }

    /// Open an external terminal with an optional docker exec command.
    /// - Parameters:
    ///   - preference: The user's terminal preference stored by `GeneralSettingsView`.
    ///   - containerID: Optional container ID to exec into.
    ///   - shell: Shell to use (e.g. "/bin/sh"). Only used when containerID is provided.
    /// - Throws: A user-actionable error when the command cannot be prepared or opened.
    static func open(
        preference: String,
        containerID: String? = nil,
        shell: String = "/bin/sh"
    ) async throws {
        let command = makeCommand(containerID: containerID, shell: shell)
        let script = makeCommandScript(command: command)
        let scriptURL = try writeCommandScript(script)

        do {
            try await openCommandScript(
                scriptURL,
                terminal: ExternalTerminalDiscovery.resolve(preference: preference)
            )
        } catch {
            removeCommandScript(at: scriptURL)
            throw error
        }
        // Only past the throwing launch — every failure path above propagates,
        // so a failed attempt never counts as a terminal open.
        Analytics.capture(
            .terminalOpened,
            properties: [
                "surface": "external",
                "target": containerID == nil ? "host" : "container",
            ])
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
            "if [ \"$arcbox_status\" -ne 0 ]; then",
            "  printf '\\nArcBox: docker exec failed with exit code %s.\\n' \"$arcbox_status\"",
            "  printf 'Check that the container is running and that the selected shell exists.\\n'",
            "fi",
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

    private static func writeCommandScript(_ source: String) throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appending(path: "arcbox-terminal-\(UUID().uuidString).command")

        do {
            try source.write(to: scriptURL, atomically: true, encoding: .utf8)
            guard chmod(scriptURL.path, S_IRUSR | S_IWUSR | S_IXUSR) == 0 else {
                let message = String(cString: strerror(errno))
                removeCommandScript(at: scriptURL)
                throw ExternalTerminalLaunchError.commandFile(message)
            }
            return scriptURL
        } catch let error as ExternalTerminalLaunchError {
            throw error
        } catch {
            logger.error("Failed to write external terminal command: \(error.localizedDescription, privacy: .public)")
            throw ExternalTerminalLaunchError.commandFile(error.localizedDescription)
        }
    }

    private static func removeCommandScript(at scriptURL: URL) {
        do {
            try FileManager.default.removeItem(at: scriptURL)
        } catch {
            logger.error("Failed to remove external terminal command: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func openCommandScript(
        _ scriptURL: URL,
        terminal: ExternalTerminalApp
    ) async throws {
        guard let appURL = terminal.appURL else {
            throw ExternalTerminalLaunchError.appUnavailable(terminal.displayName)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open(
                [scriptURL],
                withApplicationAt: appURL,
                configuration: configuration
            )
        } catch {
            logger.error("Failed to open command script: \(error.localizedDescription, privacy: .public)")
            guard let backend = terminal.appleScriptBackend else {
                throw ExternalTerminalLaunchError.launchFailed(
                    terminal.displayName,
                    error.localizedDescription
                )
            }
            try await openWithAppleScript(
                backend: backend,
                appName: terminal.displayName,
                command: fallbackCommand(for: scriptURL)
            )
        }
    }

    private static func openWithAppleScript(
        backend: ExternalTerminalApp.AppleScriptBackend,
        appName: String,
        command: String
    ) async throws {
        switch backend {
        case .terminal:
            try await openTerminalApp(appName: appName, command: command)
        case .iTerm:
            try await openITerm(appName: appName, command: command)
        }
    }

    // MARK: - Terminal.app

    private static func openTerminalApp(appName: String, command: String) async throws {
        let script = """
            tell application "Terminal"
                activate
                do script "\(escapeForAppleScript(command))"
            end tell
            """
        try await runAppleScript(script, appName: appName)
    }

    // MARK: - iTerm

    private static func openITerm(appName: String, command: String) async throws {
        let script = """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(escapeForAppleScript(command))"
                end tell
            end tell
            """
        try await runAppleScript(script, appName: appName)
    }

    // MARK: - Helpers

    /// Wrap a value in single quotes for safe shell interpolation.
    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func fallbackCommand(for scriptURL: URL) -> String {
        shellEscape(scriptURL.path)
    }

    private static func escapeForAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String, appName: String) async throws {
        let failure = await Task.detached { () -> (number: Int, message: String)? in
            guard let script = NSAppleScript(source: source) else {
                return (0, "ArcBox could not create the Automation script.")
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            guard let error else { return nil }
            return (
                (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0,
                (error[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            )
        }.value
        guard let failure else { return }

        logger.error("AppleScript error: \(failure.message, privacy: .public)")
        if failure.number == -1743 {
            throw ExternalTerminalLaunchError.automationDenied(appName)
        }
        throw ExternalTerminalLaunchError.automationFailed(appName, failure.message)
    }
}
