import Foundation

struct ExecConfig: Decodable {
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

struct ExecEnv: Decodable {
    let name: String
    let value: String
}

extension KubeConfig {
    // MARK: - Exec Credential Plugin

    /// Run an exec credential plugin command and return the bearer token.
    static func runExecPlugin(command: String, args: [String], env: [ExecEnv]) throws -> String {
        let process = Process()

        // Resolve the command path. If it's a bare name, search PATH.
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }
        if command.contains("/") {
            process.arguments = args
        }

        // Inherit current environment and overlay exec env vars
        var processEnv = ProcessInfo.processInfo.environment
        for variable in env {
            processEnv[variable.name] = variable.value
        }
        process.environment = processEnv

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        // Timeout after 15 seconds to prevent UI hang if plugin stalls.
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw KubeConfigError.execPluginFailed("exec plugin timed out after 15s")
        }

        guard process.terminationStatus == 0 else {
            throw KubeConfigError.execPluginFailed(
                "exec plugin exited with status \(process.terminationStatus)"
            )
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let credential = try JSONDecoder().decode(ExecCredential.self, from: data)

        guard let token = credential.status?.token, !token.isEmpty else {
            throw KubeConfigError.execPluginFailed("exec plugin returned no token")
        }

        return token
    }
}
