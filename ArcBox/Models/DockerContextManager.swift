import Foundation
import OSLog

/// Manages Docker CLI context switching to point at the ArcBox daemon socket.
///
/// When enabled, sets the Docker context on app startup and restores the
/// previous context on shutdown by writing to `~/.docker/config.json`.
enum DockerContextManager {
    private static let logger = Log.context
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
                guard createArcBoxContext() else {
                    logger.error("Skipping context switch — failed to create arcbox context")
                    return
                }

                // Set the current context
                var updatedConfig = config
                updatedConfig["currentContext"] = "arcbox"
                try writeConfig(updatedConfig)

                logger.info("Switched Docker context to arcbox")
            } catch {
                logger.error("Failed to switch Docker context: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Restore the Docker CLI context to what it was before ArcBox started.
    /// Always restores if a previous context was saved, regardless of the current toggle state,
    /// to avoid leaving the user's Docker CLI pointing at a dead socket.
    static func restorePreviousContext() {
        do {
            guard var config = try readConfig() else {
                logger.error("Failed to parse ~/.docker/config.json, skipping context restore to avoid data loss")
                return
            }

            // Always restore if we previously saved a context — even if the toggle was turned off since.
            if let previousContext = UserDefaults.standard.string(forKey: previousContextKey) {
                config["currentContext"] = previousContext
                try writeConfig(config)
                UserDefaults.standard.removeObject(forKey: previousContextKey)
                logger.info("Restored previous Docker context")
                return
            }

            // No saved context — only clean up currentContext if the feature is still enabled
            guard UserDefaults.standard.bool(forKey: "switchDockerContextAutomatically") else { return }
            config.removeValue(forKey: "currentContext")
            try writeConfig(config)
            logger.info("Cleared Docker context")
        } catch {
            logger.error("Failed to restore Docker context: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Creates the arcbox context in Docker's context meta store.
    /// Returns true if the context exists (created or already present), false on failure.
    @discardableResult
    private static func createArcBoxContext() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "docker", "context", "create", "arcbox",
            "--docker", "host=\(arcboxSocketPath)",
            "--description", "ArcBox Desktop",
        ]
        proc.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            logger.error("Failed to launch docker context create: \(error.localizedDescription, privacy: .public)")
            return false
        }
        // Exit 0 = created, non-zero with "already exists" = OK, otherwise fail
        if proc.terminationStatus == 0 { return true }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8) ?? ""
        if errMsg.contains("already exists") { return true }
        logger.error("docker context create failed (status \(proc.terminationStatus)): \(errMsg, privacy: .public)")
        return false
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
