import Foundation
import Security

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
            let clientKeyData = config.clientKeyData
        else {
            throw KubeConfigError.invalidCertificate(
                "Certificate auth requires client-certificate-data and client-key-data")
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
