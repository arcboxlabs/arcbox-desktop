import Foundation
import Testing

@testable import ArcBoxAuth

struct OIDCClientTests {
    @Test func formBodyPercentEncodesAndSortsFields() {
        let body = OIDCClient.formBody(["b key": "v&1", "a": "x y"])
        #expect(String(bytes: body, encoding: .utf8) == "a=x%20y&b%20key=v%261")
    }

    @Test func formBodyPreservesUnreservedCharacters() {
        let body = OIDCClient.formBody(["code_verifier": "abc-DEF_123.~"])
        #expect(String(bytes: body, encoding: .utf8) == "code_verifier=abc-DEF_123.~")
    }

    @Test func decodeTokenResponseParsesSuccess() throws {
        let json = """
            {"access_token":"at","token_type":"bearer","expires_in":3600,\
            "refresh_token":"rt","id_token":"idt","scope":"openid email"}
            """
        let response = try OIDCClient.decodeTokenResponse(data: Data(json.utf8), status: 200)
        #expect(response.accessToken == "at")
        #expect(response.tokenType == "bearer")
        #expect(response.expiresIn == 3600)
        #expect(response.refreshToken == "rt")
        #expect(response.idToken == "idt")
        #expect(response.scope == "openid email")
    }

    @Test func decodeTokenResponseToleratesMinimalPayload() throws {
        let json = #"{"access_token":"at","token_type":"bearer"}"#
        let response = try OIDCClient.decodeTokenResponse(data: Data(json.utf8), status: 200)
        #expect(response.expiresIn == nil)
        #expect(response.refreshToken == nil)
    }

    @Test func decodeTokenResponseThrowsOnHTTPError() {
        let body = #"{"error":"invalid_grant"}"#
        #expect(throws: OIDCError.tokenRequestFailed(status: 400, body: body)) {
            try OIDCClient.decodeTokenResponse(data: Data(body.utf8), status: 400)
        }
    }

    @Test func decodeTokenResponseThrowsOnMalformedJSON() {
        #expect(throws: OIDCError.tokenRequestFailed(status: 200, body: "malformed token response")) {
            try OIDCClient.decodeTokenResponse(data: Data("not json".utf8), status: 200)
        }
    }
}
