import Foundation

nonisolated enum DockerCLIResolver {
    /// Where the Docker CLI usually is, tried before `PATH`: Docker Desktop's symlink,
    /// Homebrew's, a system install.
    private static let dockerSearchPaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/usr/bin/docker",
    ]

    /// The Docker CLI: the first of `dockerSearchPaths` that is executable, else the first
    /// `docker` on `PATH`.
    ///
    /// The `PATH` search runs in-process rather than through `which docker`. `/usr/bin/which`
    /// does nothing more with the same `PATH`, and this is called synchronously from the main
    /// actor — a terminal session is opening — where a child process would have to be waited
    /// for.
    static func findDockerCLI() -> String? {
        dockerSearchPaths.first(where: FileManager.default.isExecutableFile(atPath:))
            ?? executable(named: "docker", onPath: ProcessInfo.processInfo.environment["PATH"] ?? "")
    }

    /// The first `name` in `path`'s colon-separated directories that is executable, as `which`
    /// reports it.
    static func executable(named name: String, onPath path: String) -> String? {
        path.split(separator: ":", omittingEmptySubsequences: true)
            .lazy
            .map { "\($0)/\(name)" }
            .first(where: FileManager.default.isExecutableFile(atPath:))
    }
}
