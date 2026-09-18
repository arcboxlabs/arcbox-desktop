import Foundation
import Security

// MARK: - TLS Delegate

/// URLSession delegate that pins the kubeconfig's CA and, for certificate auth, presents
/// the client identity (mTLS). Bearer-token auth only pins: its credential travels in the
/// request header.
///
/// The challenge handler is the task-level one on purpose. `URLSession.bytes(for:)`, which
/// the watch streams run on, never consults the session-level `urlSession(_:didReceive:)`,
/// while `data(for:)` falls back to the task-level method when the session-level one is
/// absent — so this single method is the only one that covers both.
@available(macOS 15.0, *)
final class KubeTLSDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let anchors: [SecCertificate]
    private let identity: SecIdentity?

    init(config: KubeConfig) throws {
        self.anchors = try KubeConfig.derBlocks(config.certificateAuthorityData).map { der in
            guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
                throw KubeConfigError.invalidCertificate("Failed to parse CA certificate")
            }
            return certificate
        }

        switch config.authMode {
        case .certificate:
            guard let clientCertData = config.clientCertificateData,
                let clientKeyData = config.clientKeyData
            else {
                throw KubeConfigError.invalidCertificate(
                    "Certificate auth requires client-certificate-data and client-key-data")
            }
            // The leaf comes first; the server already holds whatever CA follows it.
            self.identity = try Self.createIdentity(
                certData: KubeConfig.derBlocks(clientCertData)[0],
                keyPEM: clientKeyData
            )
        case .bearerToken:
            self.identity = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = protectionSpace.serverTrust
        {
            // Verify server hostname against certificate CN/SAN fields
            let sslPolicy = SecPolicyCreateSSL(true, protectionSpace.host as CFString)
            SecTrustSetPolicies(serverTrust, sslPolicy)

            // Pin the kubeconfig's CA bundle and evaluate server trust
            SecTrustSetAnchorCertificates(serverTrust, anchors as CFArray)
            SecTrustSetAnchorCertificatesOnly(serverTrust, true)
            var error: CFError?
            if SecTrustEvaluateWithError(serverTrust, &error) {
                return (.useCredential, URLCredential(trust: serverTrust))
            } else {
                return (.cancelAuthenticationChallenge, nil)
            }
        }

        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate,
            let identity
        {
            return (
                .useCredential,
                URLCredential(
                    identity: identity,
                    certificates: nil,
                    persistence: .forSession
                )
            )
        }

        return (.performDefaultHandling, nil)
    }

    // MARK: - Identity

    /// Pair a DER certificate with its PEM private key as an in-memory identity.
    static func createIdentity(certData: Data, keyPEM: Data) throws -> SecIdentity {
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
