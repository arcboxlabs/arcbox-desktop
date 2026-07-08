import CryptoKit
import Foundation
import Security

/// Proof Key for Code Exchange (RFC 7636) values for one authorization attempt.
public struct PKCECodePair: Sendable, Equatable {
    public let verifier: String
    /// `base64url(SHA256(verifier))` — the S256 challenge method.
    public let challenge: String
}

public enum PKCE {
    public static func generateCodePair() -> PKCECodePair {
        let verifier = generateRandomToken()
        return PKCECodePair(verifier: verifier, challenge: challenge(for: verifier))
    }

    /// CSPRNG token, base64url-encoded; also used for `state` and `nonce`.
    public static func generateRandomToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return Data(bytes).base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}
