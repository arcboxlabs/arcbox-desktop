import Foundation
import Testing

@testable import ArcBoxAuth

struct IDTokenClaimsTests {
    private func token(payloadJSON: String) -> String {
        let header = Data("{\"alg\":\"RS256\"}".utf8).base64URLEncodedString()
        let payload = Data(payloadJSON.utf8).base64URLEncodedString()
        return "\(header).\(payload).signature"
    }

    @Test func decodesValidToken() throws {
        let jwt = token(
            payloadJSON: """
                {"sub":"user-1","email":"april@arcbox.dev","name":"April","nonce":"n-1","exp":1751900000}
                """)
        let claims = try IDTokenClaims.decode(idToken: jwt)
        #expect(claims.subject == "user-1")
        #expect(claims.email == "april@arcbox.dev")
        #expect(claims.name == "April")
        #expect(claims.nonce == "n-1")
        #expect(claims.expiresAt == Date(timeIntervalSince1970: 1_751_900_000))
    }

    @Test func toleratesAbsentOptionalClaims() throws {
        let jwt = token(payloadJSON: #"{"sub":"user-1","exp":1751900000}"#)
        let claims = try IDTokenClaims.decode(idToken: jwt)
        #expect(claims.email == nil)
        #expect(claims.name == nil)
        #expect(claims.nonce == nil)
    }

    @Test func rejectsMissingSubject() {
        let jwt = token(payloadJSON: #"{"exp":1751900000}"#)
        #expect(throws: OIDCError.invalidIDToken) {
            try IDTokenClaims.decode(idToken: jwt)
        }
    }

    @Test func rejectsMalformedPayload() {
        #expect(throws: OIDCError.invalidIDToken) {
            try IDTokenClaims.decode(idToken: "abc.!!!not-base64!!!.def")
        }
    }

    @Test func rejectsWrongSegmentCount() {
        #expect(throws: OIDCError.invalidIDToken) {
            try IDTokenClaims.decode(idToken: "only-one-segment")
        }
    }
}
