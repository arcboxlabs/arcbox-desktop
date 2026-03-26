import Foundation
import OSLog

/// Manages Docker CLI context switching to point at the ArcBox daemon socket.
///
/// When enabled, sets the Docker context on app startup and restores the
/// previous context on shutdown by writing to `~/.docker/config.json`.
enum DockerContextManager {
    private static let logger = Logger(subsystem: "com.arcbox.desktop", category: "DockerContext")
    private static let previousContextKey = "previousDockerContext"

    private static var configPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.docker/config.json"
    }

    private static var arcboxSocketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "unix://\(home)/.arcbox/run/docker.sock"
    }

    /// Switch the Docker CLI context to use ArcBox's socket.
    /// Saves the previous context so it can be restored later.
    static func switchToArcBox() {
        guard UserDefaults.standard.bool(forKey: "switchDockerContextAutomatically") else { return }

        do {
            let config = try readConfig()

            // Save previous currentContext (if any)
            if let previousContext = config["currentContext"] as? String, previousContext != "arcbox" {
                UserDefaults.standard.set(previousContext, forKey: previousContextKey)
            }

            // Write DOCKER_HOST-based context by setting currentContext to "arcbox"
            // First, ensure the arcbox context exists in Docker's context store
            createArcBoxContext()

            // Set the current context
            var updatedConfig = config
            updatedConfig["currentContext"] = "arcbox"
            try writeConfig(updatedConfig)

            logger.info("Switched Docker context to arcbox")
        } catch {
            logger.error("Failed to switch Docker context: \(error.localizedDescription)")
        }
    }

    /// Restore the Docker CLI context to what it was before ArcBox started.
    static func restorePreviousContext() {
        guard UserDefaults.standard.bool(forKey: "switchDockerContextAutomatically") else { return }

        do {
            var config = try readConfig()
            if let previousContext = UserDefaults.standard.string(forKey: previousContextKey) {
                config["currentContext"] = previousContext
                UserDefaults.standard.removeObject(forKey: previousContextKey)
            } else {
                config.removeValue(forKey: "currentContext")
            }
            try writeConfig(config)
            logger.info("Restored previous Docker context")
        } catch {
            logger.error("Failed to restore Docker context: \(error.localizedDescription)")
        }
    }

    /// Creates the arcbox context in Docker's context meta store.
    private static func createArcBoxContext() {
        // Use docker CLI to create the context instead of manual file manipulation
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "docker", "context", "create", "arcbox",
            "--docker", "host=\(arcboxSocketPath)",
            "--description", "ArcBox Desktop",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        // Silence errors if context already exists
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // Context may already exist — that's fine
        }
    }

    // MARK: - Config File I/O

    private static func readConfig() throws -> [String: Any] {
        let url = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func writeConfig(_ config: [String: Any]) throws {
        let url = URL(fileURLWithPath: configPath)
        // Ensure ~/.docker directory exists
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
