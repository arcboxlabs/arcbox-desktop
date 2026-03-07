import Foundation

/// Lightweight wrapper around Foundation `Process` for invoking the arcbox CLI.
///
/// All process execution runs off the main actor. Callers are responsible for
/// dispatching state updates back to `@MainActor` as needed.
public struct CLIRunner: Sendable {
    /// Absolute path to the arcbox CLI binary.
    public let path: String

    /// Locate the CLI and create a runner.
    ///
    /// Search order:
    /// 1. `ARCBOX_CLI_PATH` environment variable (development override)
    /// 2. `Contents/Helpers/arcbox` inside the app bundle (production)
    public init() throws {
        if let envPath = ProcessInfo.processInfo.environment["ARCBOX_CLI_PATH"],
           FileManager.default.isExecutableFile(atPath: envPath) {
            self.path = envPath
            return
        }

        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/arcbox")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            self.path = bundled.path
            return
        }

        throw CLIRunnerError.cliNotFound
    }

    /// Run a CLI command and decode the JSON stdout into `T`.
    public func runJSON<T: Decodable & Sendable>(
        _: T.Type,
        arguments: [String]
    ) async throws -> T {
        let fullArgs = arguments + ["--format", "json"]

        let (stdout, exitCode) = try await run(arguments: fullArgs)

        guard exitCode == 0 else {
            throw CLIRunnerError.nonZeroExit(exitCode, stderr: nil)
        }

        guard let data = stdout.data(using: .utf8), !data.isEmpty else {
            throw CLIRunnerError.emptyOutput
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    /// Run a CLI command and stream NDJSON lines to a callback.
    ///
    /// Each line of stdout is decoded as `T` and passed to `onLine`. Lines that
    /// fail to decode are silently skipped.
    public func runNDJSON<T: Decodable & Sendable>(
        _: T.Type,
        arguments: [String],
        onLine: @escaping @Sendable (T) -> Void
    ) async throws {
        let fullArgs = arguments + ["--format", "json"]

        let exitCode: Int32 = try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = fullArgs
            process.standardError = FileHandle.nullDevice

            let pipe = Pipe()
            process.standardOutput = pipe

            try process.run()

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // Read lines from stdout synchronously (we're off-main).
            let handle = pipe.fileHandleForReading
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                // Split on newlines and process complete lines.
                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[buffer.startIndex..<newlineIndex]
                    buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                    if let decoded = try? decoder.decode(T.self, from: lineData) {
                        onLine(decoded)
                    }
                }
            }

            // Process any remaining data without trailing newline.
            if !buffer.isEmpty,
               let decoded = try? decoder.decode(T.self, from: buffer) {
                onLine(decoded)
            }

            process.waitUntilExit()
            return process.terminationStatus
        }.value

        guard exitCode == 0 else {
            throw CLIRunnerError.nonZeroExit(exitCode, stderr: nil)
        }
    }

    // MARK: - Private

    /// Run a process and capture stdout as a string.
    private func run(arguments: [String]) async throws -> (stdout: String, exitCode: Int32) {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardError = FileHandle.nullDevice

            let pipe = Pipe()
            process.standardOutput = pipe

            try process.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stdout = String(data: data, encoding: .utf8) ?? ""
            return (stdout, process.terminationStatus)
        }.value
    }
}

/// Errors from CLI runner operations.
public enum CLIRunnerError: Error, LocalizedError {
    case cliNotFound
    case nonZeroExit(Int32, stderr: String?)
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "arcbox CLI not found"
        case .nonZeroExit(let code, let stderr):
            "CLI exited with code \(code)\(stderr.map { ": \($0)" } ?? "")"
        case .emptyOutput:
            "CLI returned empty output"
        }
    }
}
