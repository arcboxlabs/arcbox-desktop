import Foundation
import OSLog

nonisolated private enum DockerContextError: LocalizedError {
    case invalidConfiguration(String)
    case dockerCLIUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail):
            "~/.docker/config.json is invalid: \(detail) Repair or move the file, then try again."
        case .dockerCLIUnavailable:
            "The Docker CLI was not found. Install it in a standard location, then try again."
        }
    }
}

/// Manages Docker CLI context switching to point at the ArcBox daemon socket.
///
/// When enabled, sets the Docker context on app startup and restores the
/// previous context on shutdown by writing to `~/.docker/config.json`.
nonisolated enum DockerContextManager {
    private static let logger = Log.context
    private static let previousContextKey = "previousDockerContext"
    @MainActor private static var operationTask: Task<Void, Never>?

    private static var configPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.docker/config.json"
    }

    private static var arcboxSocketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDir = profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        return "unix://\(home)/\(dataDir)/run/docker.sock"
    }

    private static var arcboxContextName: String {
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        return profile?.caseInsensitiveCompare("development") == .orderedSame ? "arcbox-dev" : "arcbox"
    }

    /// Serializes every context change in request order, including Settings and app lifecycle calls.
    @MainActor
    @discardableResult
    static func update(
        useArcBox: Bool,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) -> Task<Void, Never> {
        let previousTask = operationTask
        let task = Task {
            if let previousTask {
                await previousTask.value
            }
            do {
                if useArcBox {
                    try await switchToArcBox()
                } else {
                    try await restorePreviousContext()
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        operationTask = task
        return task
    }

    /// Switch the Docker CLI context to use ArcBox's socket.
    /// Saves the previous context so it can be restored later.
    ///
    /// `@concurrent`: `update` awaits this from the main actor, which a plain `nonisolated`
    /// async function would inherit under approachable concurrency; the config read and write
    /// below belong on the global executor.
    @concurrent
    private static func switchToArcBox() async throws {
        let config = try readConfig()
        guard let dockerPath = DockerCLIResolver.findDockerCLI() else {
            throw DockerContextError.dockerCLIUnavailable
        }

        // Keep the context from before this ArcBox session, including Docker's
        // implicit "default" context when the key is absent.
        let hadSavedContext = UserDefaults.standard.string(forKey: previousContextKey) != nil
        if !hadSavedContext {
            UserDefaults.standard.set(
                config["currentContext"] as? String ?? "default",
                forKey: previousContextKey
            )
        }

        do {
            try await DockerContextCLI(dockerPath: dockerPath).createContext(
                named: arcboxContextName, host: arcboxSocketPath, description: "ArcBox Desktop")

            var updatedConfig = config
            updatedConfig["currentContext"] = arcboxContextName
            try writeConfig(updatedConfig)
        } catch {
            if !hadSavedContext {
                UserDefaults.standard.removeObject(forKey: previousContextKey)
            }
            throw error
        }

        logger.info("Switched Docker context to \(arcboxContextName, privacy: .public)")
    }

    /// Restore the Docker CLI context to what it was before ArcBox started.
    /// Always restores if a previous context was saved, regardless of the current toggle state,
    /// to avoid leaving the user's Docker CLI pointing at a dead socket.
    @concurrent
    private static func restorePreviousContext() async throws {
        // Always restore if we previously saved a context — even if the toggle was turned off since.
        guard let previousContext = UserDefaults.standard.string(forKey: previousContextKey) else {
            // No saved context — nothing to restore.
            return
        }
        var config = try readConfig()
        config["currentContext"] = previousContext
        try writeConfig(config)
        UserDefaults.standard.removeObject(forKey: previousContextKey)
        logger.info("Restored previous Docker context")
    }

    // MARK: - Config File I/O

    /// Read and parse ~/.docker/config.json.
    /// Returns an empty dictionary if the file does not exist.
    private static func readConfig() throws -> [String: Any] {
        let url = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DockerContextError.invalidConfiguration(error.localizedDescription)
        }
        guard let json = object as? [String: Any] else {
            throw DockerContextError.invalidConfiguration("expected a JSON object.")
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
