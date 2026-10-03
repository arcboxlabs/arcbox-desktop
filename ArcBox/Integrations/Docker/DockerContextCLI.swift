import Foundation
import ProcessSupport

nonisolated enum DockerContextCLIError: LocalizedError {
    case commandFailed(String)
    case timedOut(Duration)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            "docker context create failed: \(detail)"
        case .timedOut(let timeout):
            "docker context create did not finish within "
                + "\(timeout.formatted(.units(allowed: [.seconds], width: .wide)))."
        }
    }
}

/// `docker context` through the Docker CLI at `dockerPath`.
nonisolated struct DockerContextCLI: Sendable {
    let dockerPath: String
    /// Creating a context only writes Docker's meta store. A CLI still busy after this is
    /// stuck — on a plugin, a credential helper, a hung daemon lookup — and the Settings
    /// toggle that is waiting on it must not hang with it.
    var timeout: Duration = .seconds(10)

    /// The most stderr worth keeping; an error from `docker context` is one line.
    private static let diagnosticsLimit = 64 << 10

    /// Creates the context `name` for the engine at `host`. A context of that name that
    /// already exists is left as it is.
    func createContext(named name: String, host: String, description: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerPath)
        process.arguments = [
            "context", "create", name,
            "--docker", "host=\(host)",
            "--description", description,
        ]
        process.standardOutput = FileHandle.nullDevice
        let diagnostics: Data
        do {
            diagnostics = try await runCapturingStandardError(
                process, timeout: timeout, outputLimit: Self.diagnosticsLimit)
        } catch is ProcessTimedOut {
            throw DockerContextCLIError.timedOut(timeout)
        }
        if process.terminationStatus == 0 { return }
        let detail = (String(bytes: diagnostics, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.contains("already exists") { return }
        throw DockerContextCLIError.commandFailed(
            detail.isEmpty ? "exit status \(process.terminationStatus)" : detail)
    }
}
