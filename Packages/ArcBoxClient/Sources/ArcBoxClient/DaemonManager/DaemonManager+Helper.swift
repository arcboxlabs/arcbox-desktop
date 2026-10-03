import Foundation
import OSLog
import ProcessSupport

extension DaemonManager {
    // MARK: - Helper Lifecycle

    /// Installs the privileged helper via `abctl _install` with a macOS
    /// admin password prompt when the caller has explicitly allowed it.
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
    /// admin reinstall. Refreshes user-space shell integration
    /// (`~/.arcbox/bin` Docker CLI links + PATH) only after the helper is known
    /// to be sufficient.
    ///
    /// - Throws: when the helper is missing/outdated and the privileged install
    ///   fails or does not leave a matching binary on disk. Callers surface this
    ///   in the startup UI so the user can retry (password cancel used to be
    ///   silent, leaving `/usr/local/bin/docker*` unlinked forever).
    /// - Parameter allowingAdministratorPrompt: `true` only after the user has
    ///   explicitly chosen to continue to the macOS administrator prompt.
    ///
    /// Installed helper binary path (must match arcbox-constants privileged::HELPER_BINARY).
    nonisolated static let installedHelperPath = "/usr/local/libexec/arcbox-helper"

    public func installHelper(allowingAdministratorPrompt: Bool = false) async throws {
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

        let installedVersion = try await binaryVersion(Self.installedHelperPath)
        let bundledVersion = try await binaryVersion(helper)
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

        guard allowingAdministratorPrompt else {
            helperInstalled = false
            throw HelperInstallError.approvalRequired
        }

        ClientLog.daemon.info(
            """
            Installing helper via abctl _install \
            (installed=\(installedVersion ?? "none", privacy: .public), \
            bundled=\(bundledVersion ?? "unknown", privacy: .public))
            """
        )

        let installError = try await runPrivilegedHelperInstall(abctl: abctl, helper: helper)
        if let installError {
            helperInstalled = false
            throw installError
        }

        // Verify the on-disk helper version is now ≥ the bundle. AppleScript
        // can report success while the copy/bootstrap silently no-ops.
        let postInstallVersion = try await binaryVersion(Self.installedHelperPath)
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
        throw HelperInstallError.versionMismatch(
            installed: postInstallVersion,
            expected: bundledVersion
        )
    }

    /// Run the elevated `abctl _install` AppleScript. Returns `nil` on success
    /// or a typed error describing the failure.
    private func runPrivilegedHelperInstall(
        abctl: String, helper: String
    ) async throws
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

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = errorPipe

        do {
            try await runCancellableProcess(process)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .appleScriptUnavailable
        }

        guard process.terminationStatus != 0 else {
            return nil
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let standardError = (String(bytes: errorData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = standardError.isEmpty ? "Unknown AppleScript error" : standardError
        ClientLog.daemon.warning(
            "Helper install failed (status=\(process.terminationStatus, privacy: .public)): \(message, privacy: .private)"
        )
        if message.contains("(-128)")
            || message.localizedCaseInsensitiveContains("user canceled")
            || message.localizedCaseInsensitiveContains("user cancelled")
        {
            return .userCanceled
        }
        return .installFailed(message)
    }

    /// Run `abctl setup install` as the current user to set up shell
    /// integration (PATH symlinks, completions, profile injection),
    /// then copy all bundled completions from the app bundle into
    /// the selected profile completions directory so that Docker completions etc. are
    /// available alongside `_abctl`.
    /// Non-critical — failures are logged but do not block startup.
    func installShellIntegration(abctl: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: abctl)
        process.arguments = Self.profileArguments + ["setup", "install"]
        do {
            try await runCancellableProcess(process)
            if process.terminationStatus == 0 {
                ClientLog.daemon.info("Shell integration installed via abctl setup install")
            } else {
                ClientLog.daemon.warning(
                    "abctl setup install exited with status \(process.terminationStatus)")
            }
        } catch is CancellationError {
            return
        } catch {
            ClientLog.daemon.warning(
                "Failed to run abctl setup install: \(error, privacy: .private)")
        }

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
                        "Failed to create completions dir \(destDir.path, privacy: .private): \(error, privacy: .private)"
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
                            "Failed to copy completion \(file, privacy: .private): \(error, privacy: .private)")
                    }
                }
                ClientLog.daemon.info("Installed bundled \(shell) completions")
            }
        }.value
    }

}

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

// MARK: - Errors

/// Failures while installing or verifying the privileged helper.
public enum HelperInstallError: LocalizedError, Sendable, Equatable {
    case bundledBinaryMissing(String)
    case approvalRequired
    case appleScriptUnavailable
    case userCanceled
    case installFailed(String)
    case versionMismatch(installed: String?, expected: String?)

    public var errorDescription: String? {
        switch self {
        case .bundledBinaryMissing(let name):
            return "Bundled \(name) is missing from the app. Reinstall ArcBox."
        case .approvalRequired:
            return "Administrator approval is required to install or update the helper service."
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

/// Parses `arcbox-helper --version` / RPC output into a comparable semantic version.
///
/// Formats:
/// - Independent helper: `arcbox-helper 1.0.0`
/// - Legacy workspace-tied: `arcbox-helper 0.4.12`
struct HelperVersion: Comparable, Sendable {
    private enum PrereleaseIdentifier: Comparable, Sendable {
        case numeric(String)
        case alphanumeric(String)

        static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.numeric(let lhs), .numeric(let rhs)):
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs < rhs
            case (.numeric, .alphanumeric):
                return true
            case (.alphanumeric, .numeric):
                return false
            case (.alphanumeric(let lhs), .alphanumeric(let rhs)):
                return lhs < rhs
            }
        }
    }

    let major: UInt64
    let minor: UInt64
    let patch: UInt64
    private let prerelease: [PrereleaseIdentifier]

    init(major: UInt64, minor: UInt64, patch: UInt64) {
        self.init(major: major, minor: minor, patch: patch, prerelease: [])
    }

    private init(
        major: UInt64,
        minor: UInt64,
        patch: UInt64,
        prerelease: [PrereleaseIdentifier]
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Extract a semantic version from a version line.
    static func parse(_ versionOutput: String?) -> Self? {
        guard var raw = versionOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        if raw.hasPrefix("arcbox-helper") {
            raw = raw.dropFirst("arcbox-helper".count).trimmingCharacters(in: .whitespaces)
        }

        let buildParts = raw.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        if buildParts.count == 2, !validIdentifiers(buildParts[1], allowLeadingZeroes: true) {
            return nil
        }

        let versionParts = buildParts[0].split(
            separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let parts = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let major = parseCoreIdentifier(parts[0]),
            let minor = parseCoreIdentifier(parts[1]),
            let patch = parseCoreIdentifier(parts[2])
        else {
            return nil
        }

        var prerelease: [PrereleaseIdentifier] = []
        if versionParts.count == 2 {
            let rawPrerelease = versionParts[1]
            guard validIdentifiers(rawPrerelease, allowLeadingZeroes: false) else { return nil }
            prerelease = rawPrerelease.split(separator: ".").map { identifier in
                if identifier.utf8.allSatisfy(Self.isASCIIDigit) {
                    return .numeric(String(identifier))
                }
                return .alphanumeric(String(identifier))
            }
        }

        return Self(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        return lhs.prerelease.lexicographicallyPrecedes(rhs.prerelease)
    }

    private static func parseCoreIdentifier(_ value: Substring) -> UInt64? {
        guard value.utf8.allSatisfy(isASCIIDigit),
            value.count == 1 || value.first != "0"
        else {
            return nil
        }
        return UInt64(value)
    }

    private static func validIdentifiers(
        _ value: Substring,
        allowLeadingZeroes: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        return !identifiers.isEmpty
            && identifiers.allSatisfy { identifier in
                guard !identifier.isEmpty,
                    identifier.utf8.allSatisfy({
                        isASCIIDigit($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
                    })
                else {
                    return false
                }
                return allowLeadingZeroes || !identifier.utf8.allSatisfy(isASCIIDigit)
                    || identifier.count == 1 || identifier.first != "0"
            }
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
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

/// Runs `<binary> --version` and returns the trimmed stdout (e.g. "arcbox-helper 1.0.0").
///
/// Returns `nil` when `path` is not executable, when the command fails, when it writes more
/// than 64 KiB, or when it has not exited after `timeout` (the child is terminated then).
/// Throws only `CancellationError`.
///
/// `installHelper` runs this three times per launch from the main actor, and the first launch
/// after an update — Gatekeeper scanning the fresh `arcbox-helper` — stretches each run to
/// seconds. The wait and the read therefore run off the calling actor.
nonisolated func binaryVersion(_ path: String, timeout: Duration = .seconds(5)) async throws -> String? {
    guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    process.standardError = FileHandle.nullDevice
    let output: Data
    do {
        output = try await runCapturingStandardOutput(process, timeout: timeout, outputLimit: 64 << 10)
    } catch let cancellation as CancellationError {
        throw cancellation
    } catch {
        return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    return String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}
