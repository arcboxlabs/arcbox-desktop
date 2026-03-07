import Foundation
import Observation

/// Docker tool installation state.
public enum DockerToolSetupState: Sendable, Equatable {
    case idle
    case installing(toolName: String, current: Int, total: Int, percent: Double)
    case done
    case error(String)
}

// MARK: - CLI JSON Response Type

/// Decoded NDJSON line from `arcbox docker setup --format json`.
struct DockerSetupProgressLine: Decodable, Sendable {
    let phase: String
    let name: String?
    let current: Int?
    let total: Int?
    let downloadedBytes: UInt64?
    let totalBytes: UInt64?
    let percent: UInt64?
    let error: String?
}

// MARK: - Docker Tool Setup Manager

/// Installs Docker CLI tools via the CLI and reports progress.
///
/// Follows the same Observable + NDJSON streaming pattern as `BootAssetManager`.
@Observable
@MainActor
public final class DockerToolSetupManager {
    /// Current installation state.
    public private(set) var state: DockerToolSetupState = .idle

    public init() {}

    /// Run `docker setup` via CLI with streamed progress, then `docker enable`.
    ///
    /// Non-fatal: errors are captured in `state` but never thrown.
    public func installAndEnable() async {
        guard let cli = try? CLIRunner() else { return }

        state = .installing(toolName: "", current: 0, total: 0, percent: 0)

        do {
            try await cli.runNDJSON(
                DockerSetupProgressLine.self,
                arguments: ["docker", "setup"]
            ) { [weak self] line in
                let pct = line.percent.map { Double($0) / 100.0 } ?? 0.0
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch line.phase {
                    case "error":
                        self.state = .error(line.error ?? "Docker tool install failed")
                    case "complete":
                        break
                    default:
                        self.state = .installing(
                            toolName: line.name ?? "",
                            current: line.current ?? 0,
                            total: line.total ?? 0,
                            percent: pct
                        )
                    }
                }
            }
        } catch {
            state = .error("Docker tool install failed: \(error.localizedDescription)")
            return
        }

        // Enable Docker context (non-fatal).
        try? await cli.run(arguments: ["docker", "enable"])

        state = .done
    }
}
