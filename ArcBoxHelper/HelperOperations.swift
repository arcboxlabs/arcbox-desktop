import Foundation
import OSLog
@preconcurrency import Sentry

final class HelperOperations: NSObject, ArcBoxHelperProtocol {

    // MARK: - Operation 1: Docker Socket

    func setupDockerSocket(socketPath: String, reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("setupDockerSocket: \(socketPath, privacy: .public)")
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

            guard
                let existing = try? FileManager.default.destinationOfSymbolicLink(
                    atPath: symlinkPath)
            else {
                reply(makeError("Cannot read symlink target at \(symlinkPath)"))
                return
            }

            if existing == socketPath {
                // Already pointing to the correct target — idempotent.
                reply(nil)
                return
            }

            // Replace any existing symlink — ArcBox takes ownership of docker.sock.
            do {
                try FileManager.default.removeItem(atPath: symlinkPath)
            } catch {
                reply(error as NSError)
                return
            }
        }
        // Path did not exist, or was just removed — create the symlink.
        do {
            try FileManager.default.createSymbolicLink(
                atPath: symlinkPath, withDestinationPath: socketPath)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func teardownDockerSocket(reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("teardownDockerSocket")
        let symlinkPath = "/var/run/docker.sock"
        if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath),
            isValidArcBoxSocketPath(existing)
        {
            try? FileManager.default.removeItem(atPath: symlinkPath)
        }
        // If symlink points elsewhere, leave it untouched.
        reply(nil)
    }

    // MARK: - Operation 2: CLI Tools

    func installCLITools(appBundlePath: String, reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("installCLITools: \(appBundlePath, privacy: .public)")
        // appBundlePath must be an .app bundle under a trusted location.
        let allowedPrefixes = ["/Applications/", "/Users/"]
        guard appBundlePath.hasSuffix(".app"),
            allowedPrefixes.contains(where: { appBundlePath.hasPrefix($0) })
        else {
            reply(
                makeError("appBundlePath must be under /Applications/ or /Users/ and end with .app")
            )
            return
        }

        // Actual binary path as per CLIRunner.swift:23.
        let tools: [(src: String, link: String)] = [
            ("\(appBundlePath)/Contents/MacOS/bin/abctl", "/usr/local/bin/abctl")
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

                guard isArcBoxOwnedSymlink(existing) else {
                    // Link is owned by something else (e.g. Homebrew abctl).
                    // Return error so the App can surface this, not silently skip.
                    reply(
                        makeError(
                            "/usr/local/bin/\(URL(fileURLWithPath: t.link).lastPathComponent) is owned by another tool: \(existing)"
                        ))
                    return
                }
                // Owned by a different ArcBox bundle (e.g. old install path) — replace.
                try? FileManager.default.removeItem(atPath: t.link)
            }

            do {
                try FileManager.default.createSymbolicLink(
                    atPath: t.link, withDestinationPath: t.src)
            } catch {
                reply(error as NSError)
                return
            }
        }
        reply(nil)
    }

    func uninstallCLITools(reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("uninstallCLITools")
        for link in ["/usr/local/bin/abctl"] {
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link),
                isArcBoxOwnedSymlink(target)
            {
                try? FileManager.default.removeItem(atPath: link)
            }
        }
        reply(nil)
    }

    // MARK: - Operation 3: DNS Resolver

    func setupDNSResolver(domain: String, port: Int, reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("setupDNSResolver: \(domain, privacy: .public):\(port, privacy: .public)")
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
        HelperLog.ops.info("teardownDNSResolver: \(domain, privacy: .public)")
        guard isAllowedDomain(domain) else {
            reply(makeError("Invalid domain"))
            return
        }
        try? FileManager.default.removeItem(atPath: "/etc/resolver/\(domain)")
        reply(nil)
    }

    // MARK: - Operation 4: Network routes

    func addRouteGateway(subnet: String, gateway: String, reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("addRouteGateway: \(subnet, privacy: .public) via \(gateway, privacy: .public)")
        guard isValidCIDR(subnet), isValidIPv4(gateway) else {
            reply(makeError("Invalid subnet or gateway"))
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "add", "-net", subnet, gateway]
        let pipe = Pipe()
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            reply(error as NSError)
            return
        }

        if proc.terminationStatus == 0 {
            reply(nil)
        } else {
            let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if stderr.contains("File exists") {
                reply(nil) // Idempotent — route already installed.
            } else {
                reply(makeError("route add failed: \(stderr)"))
            }
        }
    }

    func addRouteInterface(subnet: String, iface: String, reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("addRouteInterface: \(subnet, privacy: .public) -interface \(iface, privacy: .public)")
        guard isValidCIDR(subnet) else {
            reply(makeError("Invalid subnet"))
            return
        }
        // Validate interface name: must start with "bridge" and be followed by digits.
        guard iface.hasPrefix("bridge"), iface.dropFirst(6).allSatisfy(\.isNumber) else {
            reply(makeError("Invalid interface: \(iface)"))
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "add", "-net", subnet, "-interface", iface]
        let pipe = Pipe()
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            reply(error as NSError)
            return
        }

        if proc.terminationStatus == 0 {
            reply(nil)
        } else {
            let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if stderr.contains("File exists") {
                reply(nil)
            } else {
                reply(makeError("route add failed: \(stderr)"))
            }
        }
    }

    func removeRouteInterface(subnet: String, iface: String, reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("removeRouteInterface: \(subnet, privacy: .public) -interface \(iface, privacy: .public)")
        guard isValidCIDR(subnet) else {
            reply(makeError("Invalid subnet"))
            return
        }
        guard iface.hasPrefix("bridge"), iface.dropFirst(6).allSatisfy(\.isNumber) else {
            reply(makeError("Invalid interface: \(iface)"))
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "delete", "-net", subnet, "-interface", iface]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // Best-effort removal.
        }
        reply(nil)
    }

    func removeRouteGateway(subnet: String, gateway: String, reply: @escaping (NSError?) -> Void) {
        HelperLog.ops.info("removeRouteGateway: \(subnet, privacy: .public) via \(gateway, privacy: .public)")
        guard isValidCIDR(subnet), isValidIPv4(gateway) else {
            reply(makeError("Invalid subnet or gateway"))
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "delete", "-net", subnet, gateway]

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // Best-effort removal.
        }

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

    /// Checks whether a symlink target points inside an ArcBox .app bundle.
    /// Matches "ArcBox.app/", "ArcBox Desktop.app/", etc. but not unrelated paths
    /// that merely contain the substring "ArcBox".
    private func isArcBoxOwnedSymlink(_ target: String) -> Bool {
        target.range(of: #"ArcBox[^/]*\.app/"#, options: .regularExpression) != nil
    }

    private func isAllowedDomain(_ domain: String) -> Bool {
        ["arcbox.local", "arcbox.internal"].contains(domain)
    }

    private func isValidCIDR(_ cidr: String) -> Bool {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              isValidIPv4(String(parts[0])),
              let prefix = UInt8(parts[1]),
              prefix <= 32 else { return false }
        return true
    }

    private func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    private func makeError(_ msg: String) -> NSError {
        let error = NSError(
            domain: "com.arcboxlabs.desktop.helper", code: -1,
            userInfo: [NSLocalizedDescriptionKey: msg])
        HelperLog.ops.error("\(msg, privacy: .public)")
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "helper", key: "process_type")
        }
        return error
    }
}
