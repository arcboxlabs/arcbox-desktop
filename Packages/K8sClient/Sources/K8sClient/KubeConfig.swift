import Foundation
import Security

/// Parsed kubeconfig credentials for connecting to a Kubernetes API server.
@available(macOS 15.0, *)
public struct KubeConfig: Sendable {
    /// API server URL (e.g. "https://127.0.0.1:16443").
    public let server: String
    /// Base64-decoded certificate authority data from kubeconfig (PEM or DER).
    public let certificateAuthorityData: Data
    /// Base64-decoded client certificate data from kubeconfig (PEM or DER).
    public let clientCertificateData: Data
    /// Base64-decoded client private key data from kubeconfig (PEM or DER).
    public let clientKeyData: Data

    /// Parse a kubeconfig YAML string into credentials.
    ///
    /// Extracts `server`, `certificate-authority-data`, `client-certificate-data`,
    /// and `client-key-data` fields using line-based parsing (no YAML library needed
    /// since kubeconfig structure is well-known).
    public init(yaml: String) throws {
        guard let server = Self.extractValue(for: "server:", from: yaml) else {
            throw KubeConfigError.missingField("server")
        }
        guard let caB64 = Self.extractValue(for: "certificate-authority-data:", from: yaml),
              let caData = Data(base64Encoded: caB64)
        else {
            throw KubeConfigError.missingField("certificate-authority-data")
        }
        guard let certB64 = Self.extractValue(for: "client-certificate-data:", from: yaml),
              let certData = Data(base64Encoded: certB64)
        else {
            throw KubeConfigError.missingField("client-certificate-data")
        }
        guard let keyB64 = Self.extractValue(for: "client-key-data:", from: yaml),
              let keyData = Data(base64Encoded: keyB64)
        else {
            throw KubeConfigError.missingField("client-key-data")
        }

        self.server = server
        self.certificateAuthorityData = caData
        self.clientCertificateData = certData
        self.clientKeyData = keyData
    }

    /// Create a URLSession configured with mTLS credentials from this kubeconfig.
    public func makeURLSession() throws -> URLSession {
        let delegate = try KubeTLSDelegate(config: self)
        return URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
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
}

/// Errors from kubeconfig parsing.
public enum KubeConfigError: Error, Sendable {
    case missingField(String)
    case invalidCertificate(String)
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
        self.identity = try Self.createIdentity(
            certData: KubeConfig.pemToDER(config.clientCertificateData),
            keyPEM: config.clientKeyData
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
