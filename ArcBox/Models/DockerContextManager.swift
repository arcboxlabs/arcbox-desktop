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

        Task.detached {
            do {
                guard let config = try readConfig() else {
                    logger.error("Failed to parse ~/.docker/config.json, skipping context switch to avoid data loss")
                    return
                }

                // Save previous currentContext (if any)
                if let previousContext = config["currentContext"] as? String, previousContext != "arcbox" {
                    UserDefaults.standard.set(previousContext, forKey: previousContextKey)
                }

                // Ensure the arcbox context exists in Docker's context store
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
    }

    /// Restore the Docker CLI context to what it was before ArcBox started.
    static func restorePreviousContext() {
        guard UserDefaults.standard.bool(forKey: "switchDockerContextAutomatically") else { return }

        do {
            guard var config = try readConfig() else {
                logger.error("Failed to parse ~/.docker/config.json, skipping context restore to avoid data loss")
                return
            }
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
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "docker", "context", "create", "arcbox",
            "--docker", "host=\(arcboxSocketPath)",
            "--description", "ArcBox Desktop",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // Context may already exist — that's fine
        }
    }

    // MARK: - Config File I/O

    /// Read and parse ~/.docker/config.json.
    /// Returns nil if the file exists but cannot be parsed as a JSON object (to prevent clobbering).
    /// Returns an empty dictionary if the file does not exist.
    private static func readConfig() throws -> [String: Any]? {
        let url = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
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
