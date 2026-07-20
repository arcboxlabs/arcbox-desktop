import Foundation
import OSLog

extension DaemonManager {
    // MARK: - Helper Lifecycle

    /// Installs the privileged helper via `abctl _install` with a macOS
    /// admin password prompt.
    ///
    /// SMAppService.daemon() is unreliable — macOS registers the daemon
    /// as disabled without notifying the user, and System Settings provides
    /// no toggle to enable it. Instead, we use osascript to trigger the
    /// standard macOS "wants to make changes" password dialog, the same
    /// approach used by Docker Desktop and OrbStack.
    ///
    /// Skips the password prompt when the installed helper's **own crate
    /// version** is already ≥ the bundled one. That version is independent of
    /// the arcbox workspace version, so ordinary runtime bumps do not force an
    /// admin reinstall. Always refreshes user-space shell integration
    /// (`~/.arcbox/bin` Docker CLI links + PATH) so terminals keep working even
    /// when the privileged helper path is deferred or fails.
    ///
    /// - Throws: when the helper is missing/outdated and the privileged install
    ///   fails or does not leave a matching binary on disk. Callers surface this
    ///   in the startup UI so the user can retry (password cancel used to be
    ///   silent, leaving `/usr/local/bin/docker*` unlinked forever).
    ///
    /// Installed helper binary path (must match arcbox-constants privileged::HELPER_BINARY).
    nonisolated static let installedHelperPath = "/usr/local/libexec/arcbox-helper"

    public func installHelper() async throws {
        // Find abctl and helper in the app bundle.
        let bundle = Bundle.main.bundleURL
        let abctl = bundle.appendingPathComponent("Contents/MacOS/bin/abctl").path
        let helper = bundle.appendingPathComponent("Contents/MacOS/bin/arcbox-helper").path
        guard FileManager.default.isExecutableFile(atPath: abctl) else {
            throw HelperInstallError.bundledBinaryMissing("abctl")
        }
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            throw HelperInstallError.bundledBinaryMissing("arcbox-helper")
        }

        let installedVersion = binaryVersion(Self.installedHelperPath)
        let bundledVersion = binaryVersion(helper)
        let installedSemver = HelperVersion.parse(installedVersion)
        let bundledSemver = HelperVersion.parse(bundledVersion)

        // Reinstall only when installed is missing or strictly older than the
        // bundle. Equal/newer keeps the on-disk binary (no password).
        let needsInstall = HelperVersion.needsReinstall(
            installed: installedSemver,
            bundled: bundledSemver
        )

        if !needsInstall {
            helperInstalled = true
            ClientLog.daemon.info(
                """
                Helper already sufficient \
                (installed=\(installedVersion ?? "none", privacy: .public), \
                bundled=\(bundledVersion ?? "unknown", privacy: .public))
                """
            )
            await installShellIntegration(abctl: abctl)
            return
        }

        ClientLog.daemon.info(
            """
            Installing helper via abctl _install \
            (installed=\(installedVersion ?? "none", privacy: .public), \
            bundled=\(bundledVersion ?? "unknown", privacy: .public))
            """
        )

        let installError = await runPrivilegedHelperInstall(abctl: abctl, helper: helper)
        if let installError {
            helperInstalled = false
            // Still refresh user-space PATH/CLI links — these do not need root
            // and keep `docker` available via ~/.arcbox/bin when the user has
            // shell integration sourced.
            await installShellIntegration(abctl: abctl)
            throw installError
        }

        // Verify the on-disk helper version is now ≥ the bundle. AppleScript
        // can report success while the copy/bootstrap silently no-ops.
        let postInstallVersion = binaryVersion(Self.installedHelperPath)
        let postInstallSemver = HelperVersion.parse(postInstallVersion)
        if !HelperVersion.needsReinstall(installed: postInstallSemver, bundled: bundledSemver) {
            helperInstalled = true
            ClientLog.daemon.info(
                "Helper installed successfully (\(postInstallVersion ?? "unknown", privacy: .public))"
            )
            await installShellIntegration(abctl: abctl)
            return
        }

        helperInstalled = false
        await installShellIntegration(abctl: abctl)
        throw HelperInstallError.versionMismatch(
            installed: postInstallVersion,
            expected: bundledVersion
        )
    }

    /// Run the elevated `abctl _install` AppleScript. Returns `nil` on success
    /// or a typed error describing the failure.
    private func runPrivilegedHelperInstall(
        abctl: String, helper: String
    ) async
        -> HelperInstallError?
    {
        func shellQuote(_ s: String) -> String {
            "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        let profileArgs = Self.profileArguments.map(shellQuote).joined(separator: " ")
        let cmd =
            "\(shellQuote(abctl)) \(profileArgs) _install --no-daemon --no-shell --helper-path \(shellQuote(helper))"
        let script =
            "do shell script \(appleScriptStringLiteral(cmd)) with administrator privileges"

        return await Task.detached { () -> HelperInstallError? in
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else {
                return .appleScriptUnavailable
            }
            appleScript.executeAndReturnError(&error)
            if let error {
                // NSAppleScript error dictionary keys (Foundation string constants).
                let message =
                    (error["NSAppleScriptErrorMessage"] as? String)
                    ?? String(describing: error)
                let code = error["NSAppleScriptErrorNumber"] as? Int
                ClientLog.daemon.warning(
                    "Helper install failed (code=\(code.map(String.init) ?? "?", privacy: .public)): \(message, privacy: .private)"
                )
                // -128 is userCanceledErr from Authorization Services / AppleScript.
                if code == -128 || message.localizedCaseInsensitiveContains("user canceled")
                    || message.localizedCaseInsensitiveContains("user cancelled")
                {
                    return .userCanceled
                }
                return .installFailed(message)
            }
            return nil
        }.value
    }

    /// Run `abctl setup install` as the current user to set up shell
    /// integration (PATH symlinks, completions, profile injection),
    /// then copy all bundled completions from the app bundle into
    /// the selected profile completions directory so that Docker completions etc. are
    /// available alongside `_abctl`.
    /// Non-critical — failures are logged but do not block startup.
    func installShellIntegration(abctl: String) async {
        await Task.detached { @Sendable in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: abctl)
            process.arguments = Self.profileArguments + ["setup", "install"]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    ClientLog.daemon.info("Shell integration installed via abctl setup install")
                } else {
                    ClientLog.daemon.warning(
                        "abctl setup install exited with status \(process.terminationStatus)")
                }
            } catch {
                ClientLog.daemon.warning(
                    "Failed to run abctl setup install: \(error, privacy: .public)")
            }
        }.value

        await installBundledCompletions()
    }

    /// Copy all shell completions bundled in
    /// `Contents/Resources/completions/{bash,zsh,fish}/` into the
    /// user's selected profile completions directory, overwriting any
    /// existing files so bundled completion updates propagate.
    func installBundledCompletions() async {
        let bundleURL = Bundle.main.bundleURL
        await Task.detached { @Sendable in
            let fm = FileManager.default
            let bundledCompletions =
                bundleURL
                .appendingPathComponent("Contents/Resources/completions")
            guard fm.fileExists(atPath: bundledCompletions.path) else {
                ClientLog.daemon.info("No bundled completions directory found, skipping")
                return
            }

            let userCompletions = DaemonManager.profileDataDirectory
                .appendingPathComponent("completions")

            for shell in ["bash", "zsh", "fish"] {
                let srcDir = bundledCompletions.appendingPathComponent(shell)
                guard let files = try? fm.contentsOfDirectory(atPath: srcDir.path) else {
                    continue
                }
                let destDir = userCompletions.appendingPathComponent(shell)
                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                } catch {
                    ClientLog.daemon.warning(
                        "Failed to create completions dir \(destDir.path): \(error, privacy: .public)"
                    )
                    continue
                }
                for file in files {
                    let src = srcDir.appendingPathComponent(file)
                    let dest = destDir.appendingPathComponent(file)
                    do {
                        // Overwrite with the bundled version so updates propagate.
                        if fm.fileExists(atPath: dest.path) {
                            try fm.removeItem(at: dest)
                        }
                        try fm.copyItem(at: src, to: dest)
                    } catch {
                        ClientLog.daemon.warning(
                            "Failed to copy completion \(file): \(error, privacy: .public)")
                    }
                }
                ClientLog.daemon.info("Installed bundled \(shell) completions")
            }
        }.value
    }

}

// MARK: - Errors

/// Encodes an arbitrary string as one AppleScript string literal.
///
/// Shell quoting alone is insufficient because the shell command is first
/// parsed as AppleScript source. App bundle paths may contain every escaped
/// character handled here, including quotes and newlines.
func appleScriptStringLiteral(_ value: String) -> String {
    var literal = "\""
    for character in value {
        switch character {
        case "\\": literal += "\\\\"
        case "\"": literal += "\\\""
        case "\n": literal += "\\n"
        case "\r": literal += "\\r"
        case "\t": literal += "\\t"
        default: literal.append(character)
        }
    }
    literal.append("\"")
    return literal
}

/// Failures while installing or verifying the privileged helper.
public enum HelperInstallError: LocalizedError, Sendable, Equatable {
    case bundledBinaryMissing(String)
    case appleScriptUnavailable
    case userCanceled
    case installFailed(String)
    case versionMismatch(installed: String?, expected: String?)

    public var errorDescription: String? {
        switch self {
        case .bundledBinaryMissing(let name):
            return "Bundled \(name) is missing from the app. Reinstall ArcBox."
        case .appleScriptUnavailable:
            return "Could not start the administrator prompt to install the helper service."
        case .userCanceled:
            return """
                Administrator approval is required to install the helper service \
                (needed for /usr/local/bin/docker and DNS). Click Retry and enter your password.
                """
        case .installFailed(let message):
            return "Helper install failed: \(message)"
        case .versionMismatch(let installed, let expected):
            let have = installed ?? "none"
            let want = expected ?? "unknown"
            return """
                Helper service is outdated (\(have); need \(want)). \
                Click Retry and approve the administrator prompt, or run: \
                sudo abctl _install --no-daemon --no-shell
                """
        }
    }
}

// MARK: - Helper version parsing

/// Parses `arcbox-helper --version` / RPC output into a comparable semver triple.
///
/// Formats:
/// - Independent helper: `arcbox-helper 1.0.0`
/// - Legacy workspace-tied: `arcbox-helper 0.4.12`
struct HelperVersion: Comparable, Sendable {
    let major: UInt64
    let minor: UInt64
    let patch: UInt64

    /// Extract major.minor.patch from a version line.
    static func parse(_ versionOutput: String?) -> Self? {
        guard var raw = versionOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        if raw.hasPrefix("arcbox-helper") {
            raw = raw.dropFirst("arcbox-helper".count).trimmingCharacters(in: .whitespaces)
        }
        // Drop pre-release / build metadata.
        if let cut = raw.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            raw = String(raw[..<cut])
        }
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let major = UInt64(parts[0]),
            let minor = UInt64(parts[1]),
            let patch = UInt64(parts[2])
        else {
            return nil
        }
        return Self(major: major, minor: minor, patch: patch)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Whether the on-disk helper should be replaced by the bundled one.
    ///
    /// - Missing install → reinstall
    /// - Unknown bundled version → reinstall (safe default)
    /// - **Major differs** either way → reinstall (tarpc / error wire break)
    /// - Same major and installed < bundled → reinstall
    /// - Same major and installed ≥ bundled → keep (no password on app downgrade)
    static func needsReinstall(installed: Self?, bundled: Self?) -> Bool {
        guard let bundled else { return true }
        guard let installed else { return true }
        // Wire major must match. A leftover 2.x helper after downgrading the
        // app to 1.x is not "newer is fine" — force replace.
        if installed.major != bundled.major { return true }
        return installed < bundled
    }
}

/// Runs `<binary> --version` and returns the trimmed stdout
/// (e.g. "arcbox-helper 1.0.0").
/// Returns nil if the binary doesn't exist or the command fails.
func binaryVersion(_ path: String) -> String? {
    guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        // Wait with a 5-second timeout to avoid freezing the app.
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}
