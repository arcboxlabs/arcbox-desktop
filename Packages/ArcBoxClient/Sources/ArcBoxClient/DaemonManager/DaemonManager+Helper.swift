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
    /// Skips silently if the installed helper version matches the bundled one.
    /// Only prompts for password on first install or upgrade.
    /// Installed helper binary path (must match arcbox-constants privileged::HELPER_BINARY).
    nonisolated static let installedHelperPath = "/usr/local/libexec/arcbox-helper"

    public func installHelper() async {
        // Find abctl and helper in the app bundle.
        let bundle = Bundle.main.bundleURL
        let abctl = bundle.appendingPathComponent("Contents/MacOS/bin/abctl").path
        let helper = bundle.appendingPathComponent("Contents/MacOS/bin/arcbox-helper").path
        guard FileManager.default.isExecutableFile(atPath: abctl) else {
            ClientLog.daemon.warning("abctl not found in bundle, skipping helper install")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            ClientLog.daemon.warning("arcbox-helper not found in bundle, skipping helper install")
            return
        }

        // Skip if installed helper is the same version as the bundled one.
        let installedVersion = binaryVersion(Self.installedHelperPath)
        let bundledVersion = binaryVersion(helper)
        if let iv = installedVersion, let bv = bundledVersion, iv == bv {
            helperInstalled = true
            ClientLog.daemon.info("Helper \(iv, privacy: .public) already installed")
            await installShellIntegration(abctl: abctl)
            return
        }

        ClientLog.daemon.info("Installing helper via abctl _install")

        func shellQuote(_ s: String) -> String {
            "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        let cmd = "\(shellQuote(abctl)) _install --no-daemon --no-shell --helper-path \(shellQuote(helper))"
        let script = "do shell script \"\(cmd)\" with administrator privileges"

        let result = await Task.detached { () -> Bool in
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error {
                    ClientLog.daemon.warning("Helper install failed: \(error, privacy: .private)")
                    return false
                }
                return true
            }
            return false
        }.value

        helperInstalled = result
        if result {
            ClientLog.daemon.info("Helper installed successfully")
            await installShellIntegration(abctl: abctl)
        }
    }

    /// Run `abctl setup install` as the current user to set up shell
    /// integration (PATH symlinks, completions, profile injection),
    /// then copy all bundled completions from the app bundle into
    /// `~/.arcbox/completions/` so that Docker completions etc. are
    /// available alongside `_abctl`.
    /// Non-critical — failures are logged but do not block startup.
    func installShellIntegration(abctl: String) async {
        await Task.detached { @Sendable in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: abctl)
            process.arguments = ["setup", "install"]
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
    /// user's `~/.arcbox/completions/` directory, overwriting any
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

            let userCompletions = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".arcbox/completions")

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
                        "Failed to create completions dir \(destDir.path): \(error, privacy: .public)")
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

/// Runs `<binary> --version` and returns the trimmed stdout (e.g. "arcbox-helper 0.3.1").
/// Returns nil if the binary doesn't exist or the command fails.
private func binaryVersion(_ path: String) -> String? {
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
