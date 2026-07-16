import Foundation
import Testing

@testable import ArcBoxAuth

struct PKCETests {
    @Test func verifierHasRFC7636LengthAndCharset() {
        let verifier = PKCE.generateCodePair().verifier
        // 32 random bytes -> 43 base64url chars without padding.
        #expect(verifier.count == 43)
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(verifier.unicodeScalars.allSatisfy { unreserved.contains($0) })
    }

    @Test func challengeMatchesRFC7636TestVector() {
        // RFC 7636 Appendix B.
        let challenge = PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func challengeDiffersFromVerifier() {
        let pair = PKCE.generateCodePair()
        #expect(pair.challenge != pair.verifier)
    }

    @Test func tokensAreUnique() {
        #expect(PKCE.generateRandomToken() != PKCE.generateRandomToken())
    }

    @Test func tokenRespectsByteCount() {
        // 16 bytes -> 22 base64url chars without padding.
        #expect(PKCE.generateRandomToken(byteCount: 16).count == 22)
    }
}
