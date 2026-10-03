import Foundation
import OSLog
import ProcessSupport

nonisolated struct DockerMigrationSource: Equatable, Sendable {
    enum Kind: String, Sendable {
        case dockerDesktop = "docker-desktop"
        case orbStack = "orbstack"

        var displayName: String {
            switch self {
            case .dockerDesktop: "Docker Desktop"
            case .orbStack: "OrbStack"
            }
        }
    }

    let kind: Kind
    let contextName: String
    let socketPath: String
}

nonisolated struct DockerContextDescription: Decodable, Equatable, Sendable {
    let current: Bool
    let dockerEndpoint: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case current = "Current"
        case dockerEndpoint = "DockerEndpoint"
        case name = "Name"
    }
}

nonisolated private struct DockerContextInspectionError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

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

    /// Finds a Docker Desktop or OrbStack candidate without relying on the
    /// current context, which ArcBox may already have switched to itself.
    @concurrent
    static func detectMigrationSource() async throws -> DockerMigrationSource? {
        let contexts = try await readDockerContexts()
        let previousContext = UserDefaults.standard.string(forKey: previousContextKey)
        return try selectMigrationSource(
            from: contexts,
            previousContext: previousContext,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            socketExists: FileManager.default.fileExists(atPath:)
        )
    }

    static func decodeDockerContexts(_ data: Data) throws -> [DockerContextDescription] {
        try data.split(separator: UInt8(ascii: "\n")).map { line in
            try JSONDecoder().decode(DockerContextDescription.self, from: Data(line))
        }
    }

    static func selectMigrationSource(
        from contexts: [DockerContextDescription],
        previousContext: String?,
        homeDirectory: String,
        socketExists: (String) -> Bool
    ) throws -> DockerMigrationSource? {
        let candidates = contexts.compactMap { context -> DockerMigrationSource? in
            guard
                let source = migrationSource(from: context, homeDirectory: homeDirectory),
                socketExists(source.socketPath)
            else {
                return nil
            }
            return source
        }

        if let current = contexts.first(where: \.current),
            let source = candidates.first(where: { $0.contextName == current.name })
        {
            return source
        }
        if let previousContext,
            let source = candidates.first(where: { $0.contextName == previousContext })
        {
            return source
        }

        let unique = Dictionary(
            candidates.map { ("\($0.kind.rawValue):\($0.socketPath)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard unique.count <= 1 else {
            throw DockerContextInspectionError(
                "Both Docker Desktop and OrbStack are available. "
                    + "Make the environment you want to migrate the current Docker context."
            )
        }
        return unique.values.first
    }

    private static func migrationSource(
        from context: DockerContextDescription,
        homeDirectory: String
    ) -> DockerMigrationSource? {
        guard context.dockerEndpoint.hasPrefix("unix://") else { return nil }

        var socketPath = String(context.dockerEndpoint.dropFirst("unix://".count))
        if socketPath.hasPrefix("~/") {
            socketPath = "\(homeDirectory)/\(socketPath.dropFirst(2))"
        }
        socketPath = URL(fileURLWithPath: socketPath).standardizedFileURL.path

        let knownPaths = migrationSocketPaths(homeDirectory: homeDirectory)

        let kind: DockerMigrationSource.Kind
        switch socketPath {
        case knownPaths.dockerDesktop:
            kind = .dockerDesktop
        case knownPaths.orbStack:
            kind = .orbStack
        default:
            return nil
        }

        return DockerMigrationSource(
            kind: kind,
            contextName: context.name,
            socketPath: socketPath
        )
    }

    @concurrent
    static func readDockerContexts(
        dockerPath: String? = DockerCLIResolver.findDockerCLI(),
        timeout: Duration = .seconds(3)
    ) async throws -> [DockerContextDescription] {
        guard let dockerPath else {
            let paths = migrationSocketPaths(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            )
            if [paths.dockerDesktop, paths.orbStack].contains(
                where: FileManager.default.fileExists(atPath:)
            ) {
                throw DockerContextInspectionError(
                    "A supported Docker environment is running, but the Docker CLI was not found."
                )
            }
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = ["context", "ls", "--format", "{{json .}}"]
        let stderr = Pipe()
        process.standardError = stderr
        defer {
            try? stderr.fileHandleForReading.close()
            try? stderr.fileHandleForWriting.close()
        }
        let diagnostics = Task {
            try await stderr.fileHandleForReading.readToEndOfFile(limit: 64 << 10)
        }
        defer { diagnostics.cancel() }

        let output: Data
        do {
            output = try await runCapturingStandardOutput(process, timeout: timeout, outputLimit: 1 << 20)
        } catch is ProcessTimedOut {
            throw DockerContextInspectionError("Docker context inspection timed out.")
        }

        // A descendant may retain stderr after the CLI exits. Bound that drain like stdout.
        let drain = Task {
            try? await Task.sleep(for: processOutputDrainGrace)
            diagnostics.cancel()
        }
        defer { drain.cancel() }
        let errorOutput = try await diagnostics.value
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8) ?? ""
            logger.warning("Docker context inspection failed: \(message, privacy: .private)")
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DockerContextInspectionError(
                detail.isEmpty ? "Docker context inspection failed." : detail
            )
        }

        return try decodeDockerContexts(output)
    }

    private static func migrationSocketPaths(
        homeDirectory: String
    ) -> (
        dockerDesktop: String, orbStack: String
    ) {
        let home = URL(fileURLWithPath: homeDirectory)
        return (
            home.appendingPathComponent(".docker/run/docker.sock").standardizedFileURL.path,
            home.appendingPathComponent(".orbstack/run/docker.sock").standardizedFileURL.path
        )
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
