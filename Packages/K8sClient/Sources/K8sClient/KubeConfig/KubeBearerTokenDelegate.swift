import Foundation
import Security

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
