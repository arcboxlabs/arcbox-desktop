import AppKit
import ArcBoxClient
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Collects and exports a sanitized diagnostic report for troubleshooting.
///
/// The bundle includes system information, daemon status, recent OSLog entries,
/// and resource counts. It avoids obvious user-identifying details where
/// possible, but included log messages may still contain system-generated
/// identifiers or file paths beyond the home directory.
@MainActor
final class DiagnosticBundleExporter {

    /// Gather diagnostics and write a plain-text report to a user-chosen location.
    ///
    /// Shows an `NSSavePanel` so the user controls where the file goes.
    /// Returns the saved URL on success, or nil if the user cancelled.
    @discardableResult
    static func exportInteractively(
        daemonManager: DaemonManager,
        containersVM: ContainersViewModel,
        imagesVM: ImagesViewModel
    ) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostic Report"
        panel.nameFieldStringValue = "arcbox-diagnostic.txt"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let saveURL = panel.url else {
            return nil
        }

        do {
            let report = try await buildReport(
                daemonManager: daemonManager,
                containersVM: containersVM,
                imagesVM: imagesVM
            )
            let scrubbed = scrubPII(report)
            try scrubbed.write(to: saveURL, atomically: true, encoding: .utf8)
            Analytics.capture(.diagnosticExported)
            return saveURL
        } catch {
            Log.startup.error("Failed to export diagnostic report: \(error, privacy: .private)")
            return nil
        }
    }

    // MARK: - Report Building

    private static func buildReport(
        daemonManager: DaemonManager,
        containersVM: ContainersViewModel,
        imagesVM: ImagesViewModel
    ) async throws -> String {
        var sections: [String] = []

        // 1. System Information
        sections.append(systemInfoSection())

        // 2. App Information
        sections.append(appInfoSection())

        // 3. Daemon Status
        sections.append(daemonStatusSection(daemonManager))

        // 4. Resource Counts
        sections.append(resourceCountsSection(containersVM: containersVM, imagesVM: imagesVM))

        // 5. Recent OSLog entries (last 1 hour)
        sections.append(try await osLogSection())

        return sections.joined(separator: "\n\n")
    }

    private static func systemInfoSection() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        #if arch(arm64)
            let arch = "arm64"
        #elseif arch(x86_64)
            let arch = "x86_64"
        #else
            let arch = "unknown"
        #endif

        return """
            === System Information ===
            macOS: \(osVersion)
            Architecture: \(arch)
            Physical Memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB
            Processor Count: \(ProcessInfo.processInfo.processorCount)
            """
    }

    private static func appInfoSection() -> String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

        return """
            === App Information ===
            Version: \(version)
            Build: \(build)
            Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
            """
    }

    private static func daemonStatusSection(_ dm: DaemonManager) -> String {
        return """
            === Daemon Status ===
            State: \(dm.state)
            Setup Phase: \(dm.setupPhase)
            Setup Message: \(dm.setupMessage)
            DNS Resolver Installed: \(dm.dnsResolverInstalled)
            Docker Socket Linked: \(dm.dockerSocketLinked)
            Route Installed: \(dm.routeInstalled)
            VM Running: \(dm.vmRunning)
            Docker Tools Installed: \(dm.dockerToolsInstalled)
            Helper Installed: \(dm.helperInstalled)
            Reconnect Count: \(dm.reconnectCount)
            Last Message Time: \(dm.lastMessageTime?.description ?? "never")
            Error: \(dm.errorMessage ?? "none")
            """
    }

    private static func resourceCountsSection(
        containersVM: ContainersViewModel,
        imagesVM: ImagesViewModel
    ) -> String {
        return """
            === Resource Counts ===
            Containers: \(containersVM.containers.count)
            Running Containers: \(containersVM.runningCount)
            Images: \(imagesVM.images.count)
            """
    }

    private static func osLogSection() async throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let oneHourAgo = store.position(date: Date().addingTimeInterval(-3600))
        let entries = try store.getEntries(at: oneHourAgo)
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == "com.arcboxlabs.desktop" }
            .suffix(500)  // Cap to avoid huge reports
            .map { entry in
                let level: String
                switch entry.level {
                case .debug: level = "DEBUG"
                case .info: level = "INFO"
                case .notice: level = "NOTICE"
                case .error: level = "ERROR"
                case .fault: level = "FAULT"
                default: level = "?"
                }
                return "[\(entry.date.formatted(.iso8601))] [\(level)] [\(entry.category)] \(entry.composedMessage)"
            }

        if entries.isEmpty {
            return """
                === Recent Logs (last 1 hour) ===
                No log entries found for subsystem com.arcboxlabs.desktop.
                """
        }

        return "=== Recent Logs (last 1 hour, \(entries.count) entries) ===\n" + entries.joined(separator: "\n")
    }

    // MARK: - PII Scrubbing

    /// Replace the user's home directory path with "~" to prevent leaking usernames.
    private static func scrubPII(_ text: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        guard !homeDir.isEmpty else { return text }
        return text.replacingOccurrences(of: homeDir, with: "~")
    }
}
