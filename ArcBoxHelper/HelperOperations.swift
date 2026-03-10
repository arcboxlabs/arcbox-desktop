import Foundation

final class HelperOperations: NSObject, ArcBoxHelperProtocol {

    // MARK: - Operation 1: Docker Socket

    func setupDockerSocket(socketPath: String, reply: @escaping (NSError?) -> Void) {
        // Validate using regex — NOT FileManager.home, which returns /var/root when running as root.
        // Product constraint: ArcBox only supports GUI users whose home is under /Users/<name>/.
        guard isValidArcBoxSocketPath(socketPath) else {
            reply(makeError("Invalid socket path: \(socketPath)"))
            return
        }

        let symlinkPath = "/var/run/docker.sock"

        // Inspect the existing path with lstat (does not follow symlinks).
        var lstatBuf = Darwin.stat()
        if Darwin.lstat(symlinkPath, &lstatBuf) == 0 {
            // Something exists at this path.
            let isSymlink = (lstatBuf.st_mode & S_IFMT) == S_IFLNK

            guard isSymlink else {
                // A regular file or socket — not a symlink, do not remove.
                reply(makeError("/var/run/docker.sock is a regular file, not managed by ArcBox"))
                return
            }

            guard let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath) else {
                reply(makeError("Cannot read symlink target at \(symlinkPath)"))
                return
            }

            if existing == socketPath {
                // Already pointing to the correct target — idempotent.
                reply(nil); return
            }

            // Replacement policy: only replace when the existing symlink's TARGET
            // is itself an ArcBox path — regardless of whether that target is alive.
            // Any non-ArcBox symlink (live OR dead) is rejected to avoid stealing
            // sockets from Docker Desktop, OrbStack, or other runtimes.
            guard isValidArcBoxSocketPath(existing) else {
                reply(makeError("Socket owned by another runtime: \(existing)"))
                return
            }

            // Existing symlink points to a different ArcBox path — safe to replace.
            try? FileManager.default.removeItem(atPath: symlinkPath)
        }
        // Path did not exist, or was just removed — create the symlink.
        do {
            try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: socketPath)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func teardownDockerSocket(reply: @escaping (NSError?) -> Void) {
        let symlinkPath = "/var/run/docker.sock"
        if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath),
           isValidArcBoxSocketPath(existing) {
            try? FileManager.default.removeItem(atPath: symlinkPath)
        }
        // If symlink points elsewhere, leave it untouched.
        reply(nil)
    }

    // MARK: - Operation 2: CLI Tools

    func installCLITools(appBundlePath: String, reply: @escaping (NSError?) -> Void) {
        // appBundlePath must be a real app bundle under /Applications/.
        guard appBundlePath.hasPrefix("/Applications/"), appBundlePath.hasSuffix(".app") else {
            reply(makeError("appBundlePath must be under /Applications/ and end with .app"))
            return
        }

        // Actual binary path as per CLIRunner.swift:23.
        let tools: [(src: String, link: String)] = [
            ("\(appBundlePath)/Contents/MacOS/bin/abctl", "/usr/local/bin/abctl"),
        ]

        for t in tools {
            // Binary absent means the bundle is incomplete — return an error so the
            // App's startup path can decide whether to treat this as fatal or non-fatal.
            // Do NOT silently continue: a missing binary is a packaging problem, not an
            // "optional component not installed" scenario.
            guard FileManager.default.fileExists(atPath: t.src) else {
                reply(makeError("CLI binary not found in bundle: \(t.src)"))
                return
            }

            // Check what currently lives at the link path.
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: t.link) {
                if existing == t.src { continue }  // Already correct — idempotent.

                guard existing.contains("ArcBox.app") || existing.contains("/Applications/ArcBox") else {
                    // Link is owned by something else (e.g. Homebrew abctl).
                    // Return error so the App can surface this, not silently skip.
                    reply(makeError("/usr/local/bin/\(URL(fileURLWithPath: t.link).lastPathComponent) is owned by another tool: \(existing)"))
                    return
                }
                // Owned by a different ArcBox bundle (e.g. old install path) — replace.
                try? FileManager.default.removeItem(atPath: t.link)
            }

            do {
                try FileManager.default.createSymbolicLink(atPath: t.link, withDestinationPath: t.src)
            } catch {
                reply(error as NSError); return
            }
        }
        reply(nil)
    }

    func uninstallCLITools(reply: @escaping (NSError?) -> Void) {
        for link in ["/usr/local/bin/abctl"] {
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link),
               target.contains("ArcBox.app") || target.contains("/Applications/ArcBox") {
                try? FileManager.default.removeItem(atPath: link)
            }
        }
        reply(nil)
    }

    // MARK: - Operation 3: DNS Resolver

    func setupDNSResolver(domain: String, port: Int, reply: @escaping (NSError?) -> Void) {
        guard isAllowedDomain(domain), (1024...65535).contains(port) else {
            reply(makeError("Invalid domain or port"))
            return
        }
        let resolverPath = "/etc/resolver/\(domain)"
        let content = "nameserver 127.0.0.1\nport \(port)\n"
        do {
            try FileManager.default.createDirectory(
                atPath: "/etc/resolver", withIntermediateDirectories: true
            )
            try content.write(toFile: resolverPath, atomically: true, encoding: .utf8)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func teardownDNSResolver(domain: String, reply: @escaping (NSError?) -> Void) {
        guard isAllowedDomain(domain) else {
            reply(makeError("Invalid domain")); return
        }
        try? FileManager.default.removeItem(atPath: "/etc/resolver/\(domain)")
        reply(nil)
    }

    func getVersion(reply: @escaping (Int) -> Void) {
        reply(kArcBoxHelperProtocolVersion)
    }

    // MARK: - Validation

    /// Validates that path matches /Users/<name>/.arcbox/<file>.sock.
    ///
    /// Must NOT use FileManager.homeDirectoryForCurrentUser: this helper runs as root,
    /// so that API returns /var/root — not the logged-in user's home directory.
    private func isValidArcBoxSocketPath(_ path: String) -> Bool {
        // Socket path is now ~/.arcbox/run/docker.sock (DaemonManager.swift:36).
        // Pattern allows one optional subdirectory under .arcbox/ (e.g. run/).
        let pattern = #"^/Users/[^/]+/\.arcbox/(?:[^/]+/)?[^/]+\.sock$"#
        return path.range(of: pattern, options: .regularExpression) != nil
    }

    private func isAllowedDomain(_ domain: String) -> Bool {
        ["arcbox.local", "arcbox.internal"].contains(domain)
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "io.arcbox.desktop.helper", code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
