import Foundation
import Security

/// Parsed kubeconfig credentials for connecting to a Kubernetes API server.
@available(macOS 15.0, *)
public struct KubeConfig: Sendable {
    /// How the client authenticates to the API server.
    public enum AuthMode: Sendable {
        case certificate
        case bearerToken(String)
    }

    /// API server URL (e.g. "https://127.0.0.1:16443").
    public let server: String
    /// Base64-decoded certificate authority data from kubeconfig (PEM or DER).
    public let certificateAuthorityData: Data
    /// Base64-decoded client certificate data from kubeconfig (PEM or DER).
    /// Only present for certificate auth mode.
    public let clientCertificateData: Data?
    /// Base64-decoded client private key data from kubeconfig (PEM or DER).
    /// Only present for certificate auth mode.
    public let clientKeyData: Data?
    /// Authentication mode detected from the kubeconfig.
    public let authMode: AuthMode

    /// Parse a kubeconfig YAML string into credentials.
    ///
    /// Supports two authentication modes:
    /// - **Certificate auth**: `client-certificate-data` + `client-key-data` (mTLS)
    /// - **Exec credential plugin**: runs an external command to obtain a bearer token
    ///
    /// If both are present, certificate auth takes precedence.
    public init(yaml: String) throws {
        guard let server = Self.extractValue(for: "server:", from: yaml) else {
            throw KubeConfigError.missingField("server")
        }
        guard let caB64 = Self.extractValue(for: "certificate-authority-data:", from: yaml),
              let caData = Data(base64Encoded: caB64)
        else {
            throw KubeConfigError.missingField("certificate-authority-data")
        }

        self.server = server
        self.certificateAuthorityData = caData

        // Try certificate auth first
        let certB64 = Self.extractValue(for: "client-certificate-data:", from: yaml)
        let keyB64 = Self.extractValue(for: "client-key-data:", from: yaml)

        if let certB64, let keyB64,
           let certData = Data(base64Encoded: certB64),
           let keyData = Data(base64Encoded: keyB64)
        {
            self.clientCertificateData = certData
            self.clientKeyData = keyData
            self.authMode = .certificate
            return
        }

        // Fall back to exec credential plugin
        let exec = Self.extractExecConfig(from: yaml)
        if let exec {
            let token = try Self.runExecPlugin(
                command: exec.command,
                args: exec.args,
                env: exec.env
            )
            self.clientCertificateData = nil
            self.clientKeyData = nil
            self.authMode = .bearerToken(token)
            return
        }

        throw KubeConfigError.missingField("client-certificate-data or exec")
    }

    /// Create a URLSession configured with appropriate auth from this kubeconfig.
    public func makeURLSession() throws -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60

        switch authMode {
        case .certificate:
            let delegate = try KubeTLSDelegate(config: self)
            return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        case .bearerToken:
            let delegate = try KubeBearerTokenDelegate(caData: certificateAuthorityData)
            return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }

    // MARK: - Private

    /// Extract the first value for a given YAML key from the raw string.
    /// Handles both `key: value` and `key: "value"` forms.
    private static func extractValue(for key: String, from yaml: String) -> String? {
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            var value = String(trimmed.dropFirst(key.count))
                .trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes if present
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Convert PEM-encoded data to DER by stripping headers and decoding inner base64.
    /// If the data is already DER (no PEM headers), returns it as-is.
    static func pemToDER(_ data: Data) -> Data {
        guard let pem = String(data: data, encoding: .utf8),
              pem.contains("-----BEGIN") else {
            return data
        }
        let base64 = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: base64) ?? data
    }

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
        guard let execIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("exec:")
        }) else {
            return nil
        }

        // Determine indentation of the exec block's children
        let execLine = lines[execIndex]
        let execIndent = execLine.prefix(while: { $0 == " " }).count
        let childIndent = execIndent + 2 // expected child indentation

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
        process.standardError = Pipe() // discard stderr

        try process.run()
        process.waitUntilExit()

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

/// Errors from kubeconfig parsing.
public enum KubeConfigError: Error, Sendable {
    case missingField(String)
    case invalidCertificate(String)
    case execPluginFailed(String)
}

// MARK: - TLS Delegate

/// URLSession delegate that performs mTLS using kubeconfig credentials.
@available(macOS 15.0, *)
final class KubeTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let identity: SecIdentity
    private let caCertificate: SecCertificate

    init(config: KubeConfig) throws {
        // Import CA certificate (convert PEM to DER if needed)
        let caDER = KubeConfig.pemToDER(config.certificateAuthorityData)
        guard let caCert = SecCertificateCreateWithData(nil, caDER as CFData) else {
            throw KubeConfigError.invalidCertificate("Failed to parse CA certificate")
        }
        self.caCertificate = caCert

        // Create in-memory identity from client cert + key (no keychain needed)
        guard let clientCertData = config.clientCertificateData,
              let clientKeyData = config.clientKeyData else {
            throw KubeConfigError.invalidCertificate("Certificate auth requires client-certificate-data and client-key-data")
        }
        self.identity = try Self.createIdentity(
            certData: KubeConfig.pemToDER(clientCertData),
            keyPEM: clientKeyData
        )
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = protectionSpace.serverTrust
        {
            // Verify server hostname against certificate CN/SAN fields
            let sslPolicy = SecPolicyCreateSSL(true, protectionSpace.host as CFString)
            SecTrustSetPolicies(serverTrust, sslPolicy)

            // Pin the CA certificate and evaluate server trust
            SecTrustSetAnchorCertificates(serverTrust, [caCertificate] as CFArray)
            SecTrustSetAnchorCertificatesOnly(serverTrust, true)
            var error: CFError?
            if SecTrustEvaluateWithError(serverTrust, &error) {
                return (.useCredential, URLCredential(trust: serverTrust))
            } else {
                return (.cancelAuthenticationChallenge, nil)
            }
        }

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            return (.useCredential, URLCredential(
                identity: identity,
                certificates: nil,
                persistence: .forSession
            ))
        }

        return (.performDefaultHandling, nil)
    }

    // MARK: - Private

    private static func createIdentity(certData: Data, keyPEM: Data) throws -> SecIdentity {
        // Import client certificate (DER)
        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw KubeConfigError.invalidCertificate("Failed to parse client certificate")
        }

        // Import private key using SecItemImport (handles PKCS#1, PKCS#8, SEC1)
        var items: CFArray?
        var format = SecExternalFormat.formatUnknown
        var type = SecExternalItemType.itemTypePrivateKey
        let status = SecItemImport(keyPEM as CFData, nil, &format, &type, [], nil, nil, &items)
        guard status == errSecSuccess,
              let importedItems = items as? [SecKey],
              let privateKey = importedItems.first
        else {
            throw KubeConfigError.invalidCertificate("Failed to import private key (status: \(status))")
        }

        // Create in-memory identity — no keychain needed (available since macOS 10.12)
        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            throw KubeConfigError.invalidCertificate("SecIdentityCreate failed: cert and key may not match")
        }

        return identity
    }
}

// MARK: - Bearer Token Delegate

/// URLSession delegate that performs server trust verification (CA pinning) without mTLS.
/// Used with exec-based credential plugins where auth is via bearer token in the request header.
@available(macOS 15.0, *)
final class KubeBearerTokenDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let caCertificate: SecCertificate

    init(caData: Data) throws {
        let caDER = KubeConfig.pemToDER(caData)
        guard let caCert = SecCertificateCreateWithData(nil, caDER as CFData) else {
            throw KubeConfigError.invalidCertificate("Failed to parse CA certificate")
        }
        self.caCertificate = caCert
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = protectionSpace.serverTrust
        {
            let sslPolicy = SecPolicyCreateSSL(true, protectionSpace.host as CFString)
            SecTrustSetPolicies(serverTrust, sslPolicy)

            SecTrustSetAnchorCertificates(serverTrust, [caCertificate] as CFArray)
            SecTrustSetAnchorCertificatesOnly(serverTrust, true)
            var error: CFError?
            if SecTrustEvaluateWithError(serverTrust, &error) {
                return (.useCredential, URLCredential(trust: serverTrust))
            } else {
                return (.cancelAuthenticationChallenge, nil)
            }
        }

        return (.performDefaultHandling, nil)
    }
}
