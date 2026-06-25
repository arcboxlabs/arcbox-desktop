import Foundation
import OSLog

extension DaemonManager {
    // MARK: - Binary Verification

    /// Path to the daemon binary inside the app bundle.
    nonisolated private static var daemonBinaryPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent(
                "Contents/Frameworks/com.arcboxlabs.desktop.daemon.app/Contents/MacOS/com.arcboxlabs.desktop.daemon"
            ).path
    }

    /// Verify the daemon binary exists, has a valid code signature, and
    /// carries the required virtualization/hypervisor entitlements.
    ///
    /// Returns `nil` on success, or a human-readable error message on failure.
    /// Heavy work (Process spawning) runs on a detached task to keep MainActor free.
    public func verifyDaemonBinary() async -> String? {
        let path = Self.daemonBinaryPath
        return await Task.detached {
            Self.performDaemonVerification(at: path)
        }.value
    }

    /// Timeout for individual codesign invocations during verification.
    nonisolated private static let codesignTimeout: TimeInterval = 10

    nonisolated private static func performDaemonVerification(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            ClientLog.daemon.error("Daemon binary not found at \(path, privacy: .public)")
            return "Daemon binary not found at expected path."
        }

        // Step 1: verify code signature
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--strict", path]
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = FileHandle.nullDevice
        do {
            try verify.run()
            if !waitForProcess(verify, timeout: codesignTimeout) {
                return "Daemon signature verification timed out."
            }
            if verify.terminationStatus != 0 {
                ClientLog.daemon.error("Daemon signature verification failed (status \(verify.terminationStatus))")
                return "Daemon binary has an invalid code signature (codesign status \(verify.terminationStatus))."
            }
        } catch {
            ClientLog.daemon.error("codesign verify failed: \(error.localizedDescription, privacy: .private)")
            return "Failed to verify daemon signature: \(error.localizedDescription)"
        }

        // Step 2: check required entitlements
        // Read pipe data BEFORE waitUntilExit to avoid deadlock when
        // codesign output exceeds the pipe buffer capacity.
        let entProc = Process()
        entProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        entProc.arguments = ["-d", "--entitlements", "-", "--xml", path]
        let pipe = Pipe()
        entProc.standardOutput = pipe
        entProc.standardError = FileHandle.nullDevice
        do {
            try entProc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if !waitForProcess(entProc, timeout: codesignTimeout) {
                return "Daemon entitlements check timed out."
            }
            let output = String(data: data, encoding: .utf8) ?? ""

            let required = [
                "com.apple.security.virtualization",
                "com.apple.security.hypervisor",
            ]
            let missing = required.filter { !output.contains($0) }
            if !missing.isEmpty {
                let list = missing.joined(separator: ", ")
                ClientLog.daemon.error("Daemon missing entitlements: \(list, privacy: .public)")
                return
                    "Daemon binary is missing required entitlements: \(list).\nRe-sign with Developer ID and proper entitlements."
            }
        } catch {
            ClientLog.daemon.error(
                "codesign entitlements check failed: \(error.localizedDescription, privacy: .private)")
            return "Failed to read daemon entitlements: \(error.localizedDescription)"
        }

        ClientLog.daemon.info("Daemon binary verified OK (signature + entitlements)")
        return nil
    }

    /// Wait for a process to exit within a timeout. Kills the process and returns
    /// false if the deadline is exceeded.
    nonisolated private static func waitForProcess(_ process: Process, timeout: TimeInterval) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in sem.signal() }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            ClientLog.daemon.warning("codesign process timed out after \(timeout)s, killed")
            return false
        }
        return true
    }

}
