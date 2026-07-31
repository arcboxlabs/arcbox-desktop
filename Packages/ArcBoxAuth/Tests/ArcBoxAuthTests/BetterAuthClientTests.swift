import Foundation
import Testing

@testable import ArcBoxAuth

struct BetterAuthClientTests {
    // MARK: - Device code

    @Test func decodesADeviceCodeGrant() throws {
        let json = """
            {"device_code":"dev-1","user_code":"ABCD1234",\
            "verification_uri":"https://idp.example.com/device",\
            "verification_uri_complete":"https://idp.example.com/device?user_code=ABCD1234",\
            "expires_in":1800,"interval":5}
            """
        let grant = try BetterAuthClient.decodeDeviceCodeGrant(
            data: Data(json.utf8), status: 200)

        #expect(grant.deviceCode == "dev-1")
        #expect(grant.userCode == "ABCD1234")
        #expect(grant.verificationURIComplete?.query() == "user_code=ABCD1234")
        #expect(grant.expiresIn == 1800)
        #expect(grant.interval == 5)
    }

    @Test func deviceCodeGrantToleratesMissingOptionalFields() throws {
        let json = """
            {"device_code":"dev-1","user_code":"ABCD1234",\
            "verification_uri":"https://idp.example.com/device","expires_in":600}
            """
        let grant = try BetterAuthClient.decodeDeviceCodeGrant(
            data: Data(json.utf8), status: 200)

        #expect(grant.verificationURIComplete == nil)
        #expect(grant.interval == nil)
    }

    @Test func deviceCodeRequestFailureCarriesTruncatedBody() {
        let body = String(repeating: "x", count: 500)
        #expect(
            throws: AuthError.requestFailed(
                status: 500, body: String(repeating: "x", count: 200) + "…")
        ) {
            try BetterAuthClient.decodeDeviceCodeGrant(data: Data(body.utf8), status: 500)
        }
    }

    // MARK: - Token polling

    @Test func decodesAGrantedToken() throws {
        let json = #"{"access_token":"session-1","token_type":"Bearer","expires_in":2592000}"#
        let outcome = try BetterAuthClient.decodePollOutcome(data: Data(json.utf8), status: 200)

        guard case .granted(let token) = outcome else {
            Issue.record("Expected .granted, got \(outcome)")
            return
        }
        #expect(token.sessionToken == "session-1")
        let expiresAt = try #require(token.expiresAt)
        #expect(abs(expiresAt.timeIntervalSinceNow - 2_592_000) < 60)
    }

    @Test(arguments: [
        ("authorization_pending", DevicePollOutcome.authorizationPending),
        ("slow_down", DevicePollOutcome.slowDown),
    ])
    func mapsRetryableTokenErrors(code: String, expected: DevicePollOutcome) throws {
        let json = #"{"error":"\#(code)","error_description":"…"}"#
        let outcome = try BetterAuthClient.decodePollOutcome(data: Data(json.utf8), status: 400)
        #expect(outcome == expected)
    }

    @Test func mapsDenialToATerminalError() {
        let json = #"{"error":"access_denied","error_description":"denied"}"#
        #expect(throws: AuthError.authorizationDenied) {
            try BetterAuthClient.decodePollOutcome(data: Data(json.utf8), status: 400)
        }
    }

    @Test func mapsExpiryToATerminalError() {
        let json = #"{"error":"expired_token","error_description":"expired"}"#
        #expect(throws: AuthError.deviceCodeExpired) {
            try BetterAuthClient.decodePollOutcome(data: Data(json.utf8), status: 400)
        }
    }

    @Test func mapsUnknownTokenErrorsToRequestFailed() {
        let json = #"{"error":"invalid_grant","error_description":"Invalid device code"}"#
        #expect(throws: AuthError.requestFailed(status: 400, body: "Invalid device code")) {
            try BetterAuthClient.decodePollOutcome(data: Data(json.utf8), status: 400)
        }
    }

    // MARK: - Session

    @Test func decodesASessionSnapshot() throws {
        let json = """
            {"session":{"id":"s1","token":"t1","userId":"user-1",\
            "expiresAt":"2026-08-14T12:00:00.000Z"},\
            "user":{"id":"user-1","name":"Ada","email":"ada@example.com",\
            "emailVerified":true,"image":null,"createdAt":"2026-01-01T00:00:00.000Z"}}
            """
        let snapshot = try #require(
            try BetterAuthClient.decodeSessionSnapshot(data: Data(json.utf8), status: 200))

        #expect(snapshot.user.id == "user-1")
        #expect(snapshot.user.name == "Ada")
        #expect(snapshot.user.emailVerified == true)
        #expect(snapshot.user.image == nil)
        let expiresAt = try #require(snapshot.session.expiresAt)
        #expect(
            expiresAt
                == (try Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                    .parse("2026-08-14T12:00:00.000Z")))
    }

    @Test func nullSessionBodyMeansNoSession() throws {
        #expect(
            try BetterAuthClient.decodeSessionSnapshot(
                data: Data("null".utf8), status: 200) == nil)
        #expect(
            try BetterAuthClient.decodeSessionSnapshot(
                data: Data(), status: 200) == nil)
        #expect(
            try BetterAuthClient.decodeSessionSnapshot(
                data: Data("{}".utf8), status: 401) == nil)
    }

    @Test func serverFailuresThrowInsteadOfSigningOut() {
        #expect(throws: AuthError.requestFailed(status: 503, body: "unavailable")) {
            try BetterAuthClient.decodeSessionSnapshot(
                data: Data("unavailable".utf8), status: 503)
        }
    }
}
