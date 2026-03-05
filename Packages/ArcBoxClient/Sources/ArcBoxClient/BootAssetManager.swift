import Foundation
import Observation

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

/// Manages boot-assets lifecycle: seeding from app bundle, update detection, and
/// user-confirmed downloads.
///
/// Boot-assets (kernel + rootfs.erofs) are bundled inside the app at
/// `Contents/Resources/boot/{version}/` and copied to `~/.arcbox/boot/{version}/`
/// on first launch. Subsequent updates are detected by checking the CDN and
/// downloaded only after user confirmation.
@Observable
@MainActor
public final class BootAssetManager {
    /// Current boot-asset state.
    public private(set) var state: BootAssetState = .unknown

    /// The version currently in use (from boot-assets.lock).
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
    /// Reads the bundled `boot-assets.lock` to determine the version, then copies
    /// assets from `Contents/Resources/boot/{version}/` to `~/.arcbox/boot/{version}/`
    /// if they're missing.
    public func ensureAssets() async {
        guard let version = Self.readBundledVersion() else {
            // No bundled lock file — running in dev mode or assets not embedded yet.
            state = .error("boot-assets.lock not found in app bundle")
            return
        }
        currentVersion = version

        let fm = FileManager.default
        let cacheDir = "\(Self.cacheBaseDir)/\(version)"
        let manifestPath = "\(cacheDir)/manifest.json"

        // Already seeded?
        if fm.fileExists(atPath: manifestPath) {
            state = .ready(version: version)
            return
        }

        // Locate bundled assets
        guard let bundleBootDir = Self.bundledBootDir(version: version) else {
            // No bundled assets — try to prefetch via CLI
            state = .checking
            await prefetchViaCLI(version: version)
            return
        }

        state = .seeding(version: version)

        do {
            try fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

            let items = try fm.contentsOfDirectory(atPath: bundleBootDir)
            for item in items {
                let src = "\(bundleBootDir)/\(item)"
                let dst = "\(cacheDir)/\(item)"
                if fm.fileExists(atPath: dst) {
                    try fm.removeItem(atPath: dst)
                }
                try fm.copyItem(atPath: src, toPath: dst)
            }

            state = .ready(version: version)
        } catch {
            state = .error("Failed to seed boot-assets: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Check

    /// Check CDN for newer boot-asset versions. Call after a short delay post-startup.
    public func checkForUpdates() async {
        guard let current = currentVersion else { return }

        state = .checking

        // Try via bundled CLI first
        if let cliPath = Self.findCLI() {
            let newVersion = await checkUpdateViaCLI(cliPath: cliPath)
            if let newVersion, newVersion != current {
                state = .updateAvailable(current: current, new: newVersion)
                return
            }
        }

        // Fallback: direct HTTP check against CDN
        if let newVersion = await checkUpdateViaCDN() {
            if newVersion != current {
                state = .updateAvailable(current: current, new: newVersion)
                return
            }
        }

        state = .ready(version: current)
    }

    // MARK: - Download Update

    /// Download a specific boot-asset version. Call after user confirms the update.
    public func downloadUpdate(version: String) async {
        state = .downloading(version: version, progress: 0.0)

        guard let cliPath = Self.findCLI() else {
            state = .error("arcbox CLI not found — cannot download update")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["boot", "prefetch", "--asset-version", version]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            state = .error("Failed to start download: \(error.localizedDescription)")
            return
        }

        // Monitor progress from stdout (best-effort parsing)
        let handle = pipe.fileHandleForReading
        let manager = self
        Task.detached {
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let line = String(data: data, encoding: .utf8) {
                    if let pct = BootAssetManager.parseProgress(line) {
                        await MainActor.run {
                            manager.state = .downloading(
                                version: version, progress: pct)
                        }
                    }
                }
            }
        }

        process.waitUntilExit()

        if process.terminationStatus == 0 {
            currentVersion = version
            state = .ready(version: version)
        } else {
            state = .error("Download failed (exit code \(process.terminationStatus))")
        }
    }

    // MARK: - Helpers

    /// Read the boot-asset version from the bundled boot-assets.lock file.
    private nonisolated static func readBundledVersion() -> String? {
        // Look in app bundle Resources
        if let lockURL = Bundle.main.url(
            forResource: "boot-assets", withExtension: "lock") {
            return parseVersion(from: lockURL.path)
        }

        // Fallback: look alongside the executable (development)
        if let execURL = Bundle.main.executableURL {
            let devLock = execURL.deletingLastPathComponent()
                .appendingPathComponent("boot-assets.lock")
            if FileManager.default.fileExists(atPath: devLock.path) {
                return parseVersion(from: devLock.path)
            }
        }

        return nil
    }

    /// Parse version from a TOML-like boot-assets.lock file.
    private nonisolated static func parseVersion(from path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
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

    /// Path to bundled boot-assets for a given version.
    private nonisolated static func bundledBootDir(version: String) -> String? {
        let candidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/boot/\(version)")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    /// Find the arcbox CLI binary (for prefetch/update operations).
    private nonisolated static func findCLI() -> String? {
        let fm = FileManager.default

        // 1. App bundle Helpers
        let helpersCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/arcbox")
        if fm.isExecutableFile(atPath: helpersCandidate.path) {
            return helpersCandidate.path
        }

        // 2. Alongside executable (development)
        if let execURL = Bundle.main.executableURL {
            let sibling = execURL.deletingLastPathComponent()
                .appendingPathComponent("arcbox")
            if fm.isExecutableFile(atPath: sibling.path) {
                return sibling.path
            }
        }

        // 3. PATH lookup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["arcbox"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !path.isEmpty {
                    return path
                }
            }
        } catch {}

        return nil
    }

    /// Use the CLI to check for boot-asset updates.
    private func checkUpdateViaCLI(cliPath: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["boot", "status"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    if line.lowercased().contains("latest") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count >= 2 {
                            return parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
            }
        } catch {}

        return nil
    }

    /// Direct HTTP check against CDN for latest version.
    private func checkUpdateViaCDN() async -> String? {
        #if arch(arm64)
        let arch = "aarch64"
        #else
        let arch = "x86_64"
        #endif

        guard let url = URL(
            string: "https://boot.arcboxcdn.com/\(arch)/latest.json") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(
                with: data) as? [String: Any],
               let version = json["version"] as? String {
                return version
            }
        } catch {}

        return nil
    }

    /// Prefetch boot-assets via the CLI (when no bundled assets are available).
    private func prefetchViaCLI(version: String) async {
        guard let cliPath = Self.findCLI() else {
            state = .error("arcbox CLI not found — cannot prefetch boot-assets")
            return
        }

        state = .downloading(version: version, progress: 0.0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["boot", "prefetch", "--asset-version", version]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                state = .ready(version: version)
            } else {
                state = .error(
                    "Boot-asset prefetch failed (exit \(process.terminationStatus))")
            }
        } catch {
            state = .error(
                "Failed to run prefetch: \(error.localizedDescription)")
        }
    }

    /// Parse a percentage from a progress line (e.g., "Downloading... 45%").
    private nonisolated static func parseProgress(_ line: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: line,
                  range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let value = Double(line[range]) else {
            return nil
        }
        return min(value / 100.0, 1.0)
    }
}
