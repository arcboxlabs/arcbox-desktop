import Foundation
import ProcessSupport

nonisolated enum TimeMachineExclusionError: LocalizedError {
    /// `tmutil` refused: its stderr, or its exit status when it said nothing.
    case commandFailed(String)
    case timedOut(Duration)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            detail
        case .timedOut(let timeout):
            "tmutil did not finish within \(timeout.formatted(.units(allowed: [.seconds], width: .wide)))."
        }
    }
}

/// Keeps one directory in or out of Time Machine backups through `tmutil`.
nonisolated struct TimeMachineExclusion: Sendable {
    /// The `tmutil` to run; a test points this at a script.
    var tmutilPath = "/usr/bin/tmutil"
    /// `tmutil` normally answers at once, but it talks to backupd, which can be busy with a
    /// backup; a `tmutil` still running after this is stuck, and the Settings toggle waiting
    /// on it must not stay disabled for good.
    var timeout: Duration = .seconds(30)

    /// The most stderr worth keeping; a `tmutil` error is one line.
    private static let diagnosticsLimit = 64 << 10

    /// Lifts the exclusion of `path` when `included`, else excludes it. Creates `path` first:
    /// `tmutil addexclusion` refuses a path that does not exist.
    ///
    /// `@concurrent`: the Settings view awaits this from the main actor, which a plain
    /// `nonisolated` async function would inherit under approachable concurrency; the directory
    /// creation belongs on the global executor.
    @concurrent
    func update(_ path: String, includeInBackups included: Bool) async throws {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmutilPath)
        process.arguments = [included ? "removeexclusion" : "addexclusion", path]
        process.standardOutput = FileHandle.nullDevice
        let diagnostics: Data
        do {
            diagnostics = try await runCapturingStandardError(
                process, timeout: timeout, outputLimit: Self.diagnosticsLimit)
        } catch is ProcessTimedOut {
            throw TimeMachineExclusionError.timedOut(timeout)
        }
        guard process.terminationStatus != 0 else { return }
        let detail = (String(bytes: diagnostics, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw TimeMachineExclusionError.commandFailed(
            detail.isEmpty ? "tmutil exited with status \(process.terminationStatus)." : detail)
    }
}
