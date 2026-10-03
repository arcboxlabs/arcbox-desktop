import Foundation
import Testing
import os

@testable import ArcBoxAuth

struct BetterAuthClientTests {
    // MARK: - Session isolation

    @Test func defaultSessionConfigurationDisablesCookies() {
        let configuration = BetterAuthClient.makeSessionConfiguration()

        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
    }

    @Test func responsesCannotSetCookiesForLaterRequests() async throws {
        CookieRecordingURLProtocol.reset()
        let configuration = BetterAuthClient.makeSessionConfiguration()
        configuration.protocolClasses = [CookieRecordingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = BetterAuthClient(session: session)

        _ = try await client.requestDeviceCode(configuration: AuthTestSupport.configuration)
        _ = try await client.requestDeviceCode(configuration: AuthTestSupport.configuration)

        let cookieHeaders = CookieRecordingURLProtocol.cookieHeaders
        #expect(cookieHeaders.count == 2)
        #expect(cookieHeaders.allSatisfy { $0 == nil })
    }

    @Test func propagatesURLSessionCancellation() async {
        let configuration = BetterAuthClient.makeSessionConfiguration()
        configuration.protocolClasses = [CancellationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = BetterAuthClient(session: session)

        await #expect(throws: CancellationError.self) {
            try await client.requestDeviceCode(configuration: AuthTestSupport.configuration)
        }
    }

    @Test func legacyCleanupIsLimitedToBetterAuthCookies() throws {
        let secureToken = try cookie(named: "__Secure-better-auth.session_token")
        let secureData = try cookie(named: "__Secure-better-auth.session_data")
        let localToken = try cookie(named: "better-auth.session_token")
        let unrelated = try cookie(named: "arcbox-preference")
        let cookies = [secureToken, secureData, localToken, unrelated]
        let storage = HTTPCookieStorage.shared
        cookies.forEach(storage.setCookie)
        defer { cookies.forEach(storage.deleteCookie) }

        BetterAuthClient.clearLegacyCookies(for: AuthTestSupport.configuration.issuerURL)

        let remainingNames =
            storage.cookies(for: AuthTestSupport.configuration.issuerURL)?
            .map(\.name) ?? []
        #expect(!remainingNames.contains(secureToken.name))
        #expect(!remainingNames.contains(secureData.name))
        #expect(!remainingNames.contains(localToken.name))
        #expect(remainingNames.contains(unrelated.name))
    }

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

    private func cookie(named name: String) throws -> HTTPCookie {
        try #require(
            HTTPCookie(properties: [
                .name: name,
                .value: "opaque",
                .domain: "idp.example.com",
                .path: "/",
                .secure: "TRUE",
            ]))
    }
}

private class CookieRecordingURLProtocol: URLProtocol {
    private static let storage = OSAllocatedUnfairLock(initialState: [String?]())

    static var cookieHeaders: [String?] { storage.withLock { $0 } }

    static func reset() {
        storage.withLock { $0.removeAll() }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { fatalError("Stub request is missing its URL") }
        let cookieHeader = request.value(forHTTPHeaderField: "Cookie")
        Self.storage.withLock {
            $0.append(cookieHeader)
        }
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Set-Cookie":
                        "__Secure-better-auth.session_data=opaque; Path=/; Secure; HttpOnly"
                ])
        else {
            fatalError("Failed to create stub response")
        }
        let body = Data(
            """
            {"device_code":"dev-1","user_code":"ABCD1234",\
            "verification_uri":"https://idp.example.com/device","expires_in":1800}
            """.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private class CancellationURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}
