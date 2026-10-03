import Foundation
import ProcessSupport

struct ExecConfig: Decodable, Sendable {
    let command: String
    let args: [String]
    let env: [ExecEnv]

    private enum CodingKeys: String, CodingKey {
        case command
        case args
        case env
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decode(String.self, forKey: .command)
        self.args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        self.env = try container.decodeIfPresent([ExecEnv].self, forKey: .env) ?? []
    }
}

struct ExecEnv: Decodable, Sendable {
    let name: String
    let value: String
}

extension KubeConfig {
    // MARK: - Exec Credential Plugin

    /// The most stdout an exec plugin may write. A credential is a few KiB of JSON.
    private static let execPluginOutputLimit = 1 << 20

    /// Runs an exec credential plugin and returns the bearer token it prints.
    ///
    /// The wait and the stdout read run off the calling actor: the app resolves a kubeconfig
    /// from the main actor, and a plugin such as `aws eks get-token` takes seconds. A plugin
    /// still running after `timeout`, or writing past `execPluginOutputLimit`, is terminated.
    nonisolated static func runExecPlugin(
        command: String,
        args: [String],
        env: [ExecEnv],
        timeout: Duration = .seconds(15)
    ) async throws -> String {
        let process = Process()
        // A bare command name is resolved on PATH by env(1).
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }

        // Inherit current environment and overlay exec env vars
        var processEnv = ProcessInfo.processInfo.environment
        for variable in env {
            processEnv[variable.name] = variable.value
        }
        process.environment = processEnv
        process.standardError = FileHandle.nullDevice

        let output: Data
        do {
            output = try await runCapturingStandardOutput(
                process, timeout: timeout, outputLimit: execPluginOutputLimit)
        } catch is ProcessTimedOut {
            throw KubeConfigError.execPluginFailed(
                "exec plugin timed out after \(timeout.components.seconds)s"
            )
        } catch let exceeded as ProcessOutputLimitExceeded {
            throw KubeConfigError.execPluginFailed(
                "exec plugin wrote more than \(exceeded.limit) bytes"
            )
        }

        guard process.terminationStatus == 0 else {
            throw KubeConfigError.execPluginFailed(
                "exec plugin exited with status \(process.terminationStatus)"
            )
        }

        let credential = try JSONDecoder().decode(ExecCredential.self, from: output)

        guard let token = credential.status?.token, !token.isEmpty else {
            throw KubeConfigError.execPluginFailed("exec plugin returned no token")
        }

        return token
    }
}
