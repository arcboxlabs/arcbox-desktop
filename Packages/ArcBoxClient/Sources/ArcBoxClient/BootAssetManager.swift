import CryptoKit
import Foundation
import Observation
import OSLog

/// Boot-asset lifecycle state.
public enum BootAssetState: Sendable, Equatable {
    case unknown
    case checking
    case ready(version: String)
    /// Initial seeding from app bundle to cache.
    case seeding(version: String)
    case updateAvailable(current: String, new: String)
    case downloading(version: String, progress: Double)
    case error(String)
}

// MARK: - CLI JSON Response Types

/// Decoded response from `arcbox boot status --format json`.
struct BootStatusResponse: Decodable, Sendable {
    let version: String
    let arch: String
    let cacheDir: String
    let cached: Bool
    let assets: BootAssetDetails?
    let manifest: BootManifestInfo?
    let latestVersion: String?
    let updateAvailable: Bool
}

struct BootAssetDetails: Decodable, Sendable {
    let kernelPath: String
    let kernelSize: UInt64
    let rootfsPath: String
    let rootfsSize: UInt64
}

struct BootManifestInfo: Decodable, Sendable {
    let schemaVersion: UInt32
    let builtAt: String
    let sourceSha: String?
}

/// Decoded NDJSON line from `arcbox boot prefetch --format json`.
struct PrefetchProgressLine: Decodable, Sendable {
    let phase: String
    let name: String?
    let current: Int?
    let total: Int?
    let downloadedBytes: UInt64?
    let totalBytes: UInt64?
    let percent: UInt64?
    let error: String?
}

// MARK: - Boot Asset Manager

/// Manages boot-assets lifecycle: seeding from app bundle, update detection, and
/// user-confirmed downloads.
///
/// Boot-assets (kernel + rootfs.erofs) are bundled inside the app at
/// `Contents/Resources/boot/{version}/` and copied to `~/.arcbox/boot/{version}/`
/// on first launch. Subsequent updates are detected via `arcbox boot status`
/// JSON output and downloaded only after user confirmation.
@Observable
@MainActor
public final class BootAssetManager {
    /// Current boot-asset state.
    public private(set) var state: BootAssetState = .unknown

    /// The version currently in use.
    public private(set) var currentVersion: String?

    /// Cache directory: ~/.arcbox/boot/
    private nonisolated static let cacheBaseDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.arcbox/boot"
    }()

    public init() {}

    // MARK: - Seed from Bundle

    /// Ensure boot-assets are present in the user cache.
    ///
    /// Asks the CLI for the current version and cache state, then:
    /// 1. If already cached → ready
    /// 2. If bundled assets exist → seed (copy) them to cache
    /// 3. Otherwise → download via CLI
    public func ensureAssets() async {
        state = .checking

        guard let cli = try? CLIRunner() else {
            // No CLI available — try legacy bundle-only seeding.
            await ensureAssetsWithoutCLI()
            return
        }

        let status: BootStatusResponse
        do {
            status = try await cli.runJSON(
                BootStatusResponse.self,
                arguments: ["boot", "status", "--offline"])
        } catch {
            state = .error("Failed to query boot status: \(error.localizedDescription)")
            return
        }

        currentVersion = status.version

        if status.cached {
            state = .ready(version: status.version)
            return
        }

        // Try to seed from app bundle.
        if let bundleDir = Self.bundledBootDir(version: status.version) {
            state = .seeding(version: status.version)

            let cacheDir = "\(Self.cacheBaseDir)/\(status.version)"
            let result: Result<Void, Error> = await Task.detached(priority: .utility) {
                let fm = FileManager.default
                do {
                    try fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
                    let items = try fm.contentsOfDirectory(atPath: bundleDir)
                    for item in items {
                        let src = "\(bundleDir)/\(item)"
                        let dst = "\(cacheDir)/\(item)"
                        if fm.fileExists(atPath: dst) {
                            try fm.removeItem(atPath: dst)
                        }
                        try fm.copyItem(atPath: src, toPath: dst)
                    }
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success:
                state = .ready(version: status.version)
            case .failure(let error):
                state = .error("Failed to seed boot-assets: \(error.localizedDescription)")
            }
            return
        }

        // No bundled assets — download via CLI.
        await downloadViaCLI(cli: cli, version: status.version)
    }

    // MARK: - Update Check

    /// Check for newer boot-asset versions via the CLI (queries CDN).
    public func checkForUpdates() async {
        guard let current = currentVersion else { return }

        guard let cli = try? CLIRunner() else { return }

        let status: BootStatusResponse
        do {
            // Online mode: CLI will check CDN for latest version.
            status = try await cli.runJSON(
                BootStatusResponse.self,
                arguments: ["boot", "status"])
        } catch {
            // Network errors during update check are non-fatal.
            state = .ready(version: current)
            return
        }

        if status.updateAvailable, let latest = status.latestVersion {
            state = .updateAvailable(current: current, new: latest)
        } else {
            state = .ready(version: current)
        }
    }

    // MARK: - Download Update

    /// Download a specific boot-asset version. Call after user confirms the update.
    public func downloadUpdate(version: String) async {
        guard let cli = try? CLIRunner() else {
            state = .error("arcbox CLI not found — cannot download update")
            return
        }

        await downloadViaCLI(cli: cli, version: version)
    }

    // MARK: - Internal

    /// Download boot-assets via CLI with NDJSON progress streaming.
    private func downloadViaCLI(cli: CLIRunner, version: String) async {
        state = .downloading(version: version, progress: 0.0)

        do {
            try await cli.runNDJSON(
                PrefetchProgressLine.self,
                arguments: ["boot", "prefetch", "--asset-version", version]
            ) { [weak self] line in
                // Progress updates must be dispatched to MainActor.
                let pct = line.percent.map { Double($0) / 100.0 } ?? 0.0
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if line.phase == "error" {
                        self.state = .error(line.error ?? "Download failed")
                    } else if line.phase != "complete" {
                        self.state = .downloading(version: version, progress: pct)
                    }
                }
            }
            currentVersion = version
            state = .ready(version: version)
        } catch {
            state = .error("Download failed: \(error.localizedDescription)")
        }
    }

    /// Fallback: seed from bundle without CLI (e.g., first launch before CLI is bundled).
    private func ensureAssetsWithoutCLI() async {
        // Look for bundled boot-assets.lock to get the version.
        guard let lockURL = Bundle.main.url(forResource: "boot-assets", withExtension: "lock"),
              let content = try? String(contentsOf: lockURL, encoding: .utf8),
              let version = Self.parseVersionFromLock(content) else {
            // No bundled lock file — leave as .unknown.
            state = .unknown
            return
        }

        currentVersion = version

        let cacheDir = "\(Self.cacheBaseDir)/\(version)"
        let manifestPath = "\(cacheDir)/manifest.json"

        let alreadyCached = await Task.detached {
            FileManager.default.fileExists(atPath: manifestPath)
        }.value

        if alreadyCached {
            state = .ready(version: version)
            return
        }

        guard let bundleDir = Self.bundledBootDir(version: version) else {
            state = .error("No CLI and no bundled boot-assets for \(version)")
            return
        }

        state = .seeding(version: version)

        let result: Result<Void, Error> = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            do {
                try fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
                let items = try fm.contentsOfDirectory(atPath: bundleDir)
                for item in items {
                    let src = "\(bundleDir)/\(item)"
                    let dst = "\(cacheDir)/\(item)"
                    if fm.fileExists(atPath: dst) {
                        try fm.removeItem(atPath: dst)
                    }
                    try fm.copyItem(atPath: src, toPath: dst)
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            state = .ready(version: version)
        case .failure(let error):
            state = .error("Failed to seed boot-assets: \(error.localizedDescription)")
        }
    }

    // MARK: - Runtime Binary Seeding

    private nonisolated static let runtimeDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.arcbox/runtime"
    }()

    /// Seed bundled runtime binaries (dockerd, containerd, k3s, etc.) from
    /// `Contents/Resources/runtime/` to `~/.arcbox/runtime/`, preserving the
    /// subdirectory structure (bin/, kernel/, etc.).
    public func seedRuntimeBinaries() async {
        let bundleDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/runtime")

        let destBase = Self.runtimeDir

        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: bundleDir.path) else {
                ClientLog.startup.info("No bundled runtime directory, skipping seed")
                return
            }

            guard let enumerator = fm.enumerator(atPath: bundleDir.path) else {
                return
            }

            while let relativePath = enumerator.nextObject() as? String {
                let src = bundleDir.appendingPathComponent(relativePath).path
                let dst = "\(destBase)/\(relativePath)"

                var isDir: ObjCBool = false
                fm.fileExists(atPath: src, isDirectory: &isDir)
                if isDir.boolValue {
                    try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
                    continue
                }

                if fm.fileExists(atPath: dst), fileSHA256(src) == fileSHA256(dst) {
                    continue
                }
                try? fm.removeItem(atPath: dst)

                ClientLog.startup.info("Seeding runtime binary: \(relativePath, privacy: .public)")
                do {
                    try fm.createDirectory(
                        atPath: (dst as NSString).deletingLastPathComponent,
                        withIntermediateDirectories: true)
                    try fm.copyItem(atPath: src, toPath: dst)
                } catch {
                    ClientLog.startup.error("Failed to seed \(relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }.value
    }

    /// Seed bundled arcbox-agent from `Contents/Resources/bin/` to `~/.arcbox/bin/`.
    /// The daemon expects the agent at `~/.arcbox/bin/arcbox-agent` for guest VMs.
    public func seedAgentBinary() async {
        let bundleBin = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/bin/arcbox-agent")

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let destDir = "\(home)/.arcbox/bin"
        let destPath = "\(destDir)/arcbox-agent"

        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: bundleBin.path) else {
                ClientLog.startup.info("No bundled arcbox-agent, skipping seed")
                return
            }

            if fm.fileExists(atPath: destPath),
               fileSHA256(bundleBin.path) == fileSHA256(destPath)
            {
                return
            }

            do {
                try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
                try? fm.removeItem(atPath: destPath)
                try fm.copyItem(atPath: bundleBin.path, toPath: destPath)
                ClientLog.startup.info("Seeded arcbox-agent → \(destPath, privacy: .public)")
            } catch {
                ClientLog.startup.error("Failed to seed arcbox-agent: \(error.localizedDescription, privacy: .public)")
            }
        }.value
    }

    // MARK: - Helpers

    /// Path to bundled boot-assets for a given version.
    private nonisolated static func bundledBootDir(version: String) -> String? {
        let candidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/assets/\(version)")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    /// Parse version from boot-assets.lock TOML content (fallback only).
    private nonisolated static func parseVersionFromLock(_ content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("version") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    return parts[1]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
        return nil
    }
}

/// SHA-256 digest of a file's contents. Returns nil on read failure.
private func fileSHA256(_ path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
