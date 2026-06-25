import Foundation

extension KubeConfig {
    // MARK: - Exec Credential Plugin

    struct ExecConfig {
        let command: String
        let args: [String]
        let env: [(String, String)]
    }

    /// Extract the exec credential plugin config from kubeconfig YAML.
    static func extractExecConfig(from yaml: String) -> ExecConfig? {
        let lines = yaml.components(separatedBy: .newlines)

        // Find the "exec:" line
        guard
            let execIndex = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("exec:")
            })
        else {
            return nil
        }

        // Determine indentation of the exec block's children
        let execLine = lines[execIndex]
        let execIndent = execLine.prefix(while: { $0 == " " }).count
        let childIndent = execIndent + 2  // expected child indentation

        // Collect lines belonging to the exec block
        var command: String?
        var args: [String] = []
        var env: [(String, String)] = []
        var inArgs = false
        var inEnv = false
        var pendingEnvName: String?

        for i in (execIndex + 1)..<lines.count {
            let line = lines[i]
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }

            let currentIndent = line.prefix(while: { $0 == " " }).count
            // If we've de-dented back to or past the exec level, stop
            if currentIndent <= execIndent && !stripped.isEmpty {
                break
            }

            // Direct children of exec (at childIndent level)
            if currentIndent == childIndent {
                inArgs = false
                inEnv = false

                if stripped.hasPrefix("command:") {
                    command = stripped.dropFirst("command:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                } else if stripped.hasPrefix("args:") {
                    inArgs = true
                } else if stripped.hasPrefix("env:") {
                    inEnv = true
                }
                // Ignore apiVersion, interactiveMode, etc.
                continue
            }

            // Deeper children
            if inArgs && stripped.hasPrefix("- ") {
                let arg = stripped.dropFirst(2)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                args.append(arg)
            } else if inEnv {
                if stripped.hasPrefix("- name:") {
                    pendingEnvName = stripped.dropFirst("- name:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                } else if stripped.hasPrefix("name:") {
                    pendingEnvName = stripped.dropFirst("name:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                } else if stripped.hasPrefix("value:"), let name = pendingEnvName {
                    let value = stripped.dropFirst("value:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    env.append((name, value))
                    pendingEnvName = nil
                }
            }
        }

        guard let command else { return nil }
        return ExecConfig(command: command, args: args, env: env)
    }

    /// Run an exec credential plugin command and return the bearer token.
    static func runExecPlugin(command: String, args: [String], env: [(String, String)]) throws -> String {
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
        for (name, value) in env {
            processEnv[name] = value
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
