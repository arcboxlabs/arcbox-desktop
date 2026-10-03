import Foundation
import OSLog
import ProcessSupport

extension DaemonManager {
    // MARK: - Binary Verification

    /// Path to the daemon binary inside the app bundle.
    nonisolated private static var daemonBinaryPath: String {
        let daemonLabel = Self.daemonLabel
        return Bundle.main.bundleURL
            .appendingPathComponent(
                "Contents/Frameworks/\(daemonLabel).app/Contents/MacOS/\(daemonLabel)"
            ).path
    }

    /// Verify the daemon binary exists, has a valid code signature, and
    /// carries the required virtualization/hypervisor entitlements.
    ///
    /// Returns `nil` on success, or a human-readable error message on failure.
    /// Both `codesign` runs are awaited, not waited for, so the main actor stays free.
    public func verifyDaemonBinary() async -> String? {
        await Self.performDaemonVerification(at: Self.daemonBinaryPath)
    }

    /// A `codesign` still running after this is terminated and reported as a timeout.
    nonisolated private static let codesignTimeout: Duration = .seconds(10)

    /// The entitlements plist of the daemon is a few KiB.
    nonisolated private static let entitlementsOutputLimit = 1 << 20

    nonisolated private static func performDaemonVerification(at path: String) async -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            ClientLog.daemon.error("Daemon binary not found at \(path, privacy: .private)")
            return "Daemon binary not found at expected path."
        }

        // Step 1: verify code signature
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--strict", path]
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = FileHandle.nullDevice
        do {
            try await runCancellableProcess(verify, timeout: codesignTimeout)
        } catch is ProcessTimedOut {
            ClientLog.daemon.warning("codesign --verify did not finish within \(codesignTimeout) and was killed")
            return "Daemon signature verification timed out."
        } catch {
            ClientLog.daemon.error("codesign verify failed: \(error.localizedDescription, privacy: .private)")
            return "Failed to verify daemon signature: \(error.localizedDescription)"
        }
        if verify.terminationStatus != 0 {
            ClientLog.daemon.error("Daemon signature verification failed (status \(verify.terminationStatus))")
            return "Daemon binary has an invalid code signature (codesign status \(verify.terminationStatus))."
        }

        // Step 2: check required entitlements
        let entitlements = Process()
        entitlements.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        entitlements.arguments = ["-d", "--entitlements", "-", "--xml", path]
        entitlements.standardError = FileHandle.nullDevice
        let output: Data
        do {
            output = try await runCapturingStandardOutput(
                entitlements, timeout: codesignTimeout, outputLimit: entitlementsOutputLimit)
        } catch is ProcessTimedOut {
            ClientLog.daemon.warning("codesign --entitlements did not finish within \(codesignTimeout) and was killed")
            return "Daemon entitlements check timed out."
        } catch {
            ClientLog.daemon.error(
                "codesign entitlements check failed: \(error.localizedDescription, privacy: .private)")
            return "Failed to read daemon entitlements: \(error.localizedDescription)"
        }

        let plist = String(bytes: output, encoding: .utf8) ?? ""
        let required = [
            "com.apple.security.virtualization",
            "com.apple.security.hypervisor",
        ]
        let missing = required.filter { !plist.contains($0) }
        if !missing.isEmpty {
            let missingEntitlements = missing.joined(separator: ", ")
            ClientLog.daemon.error("Daemon missing entitlements: \(missingEntitlements, privacy: .public)")
            return
                "Daemon binary is missing required entitlements: \(missingEntitlements).\nRe-sign with Developer ID and proper entitlements."
        }

        ClientLog.daemon.info("Daemon binary verified OK (signature + entitlements)")
        return nil
    }
}
