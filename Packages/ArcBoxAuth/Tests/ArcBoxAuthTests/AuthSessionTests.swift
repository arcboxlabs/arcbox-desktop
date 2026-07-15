import Foundation
import Testing

@testable import ArcBoxAuth

@MainActor
struct AuthSessionTests {
    private let provider = FakeOIDCProvider()
    private let store = InMemoryTokenStore()

    private func makeSession() -> AuthSession {
        AuthSession(
            configuration: AuthTestSupport.configuration,
            provider: provider,
            tokenStore: store)
    }

    private func makeRestoredSession() async -> AuthSession {
        let session = makeSession()
        await session.restoreSession()
        return session
    }

    private func freshTokens(refreshToken: String? = "refresh-1") -> StoredTokens {
        StoredTokens(
            accessToken: "access-1",
            refreshToken: refreshToken,
            idToken: AuthTestSupport.idToken(subject: "user-1", email: "april@arcbox.dev"),
            expiresAt: Date().addingTimeInterval(3600))
    }

    private func expiredTokens(refreshToken: String? = "refresh-1") -> StoredTokens {
        var tokens = freshTokens(refreshToken: refreshToken)
        tokens.expiresAt = Date().addingTimeInterval(-10)
        return tokens
    }

    // MARK: - Restore

    @Test func initDoesNotReadFromStore() throws {
        try store.save(freshTokens())
        let session = makeSession()

        #expect(store.loadCalls == 0)
        #expect(session.status == .signedOut)
        #expect(session.identity == nil)
    }

    @Test func restoreSessionRestoresStoredTokens() async throws {
        try store.save(freshTokens())
        let session = makeSession()
        await session.restoreSession()

        #expect(session.status == .signedIn)
        #expect(session.identity?.subject == "user-1")
        #expect(session.identity?.email == "april@arcbox.dev")
        #expect(store.loadCalls == 1)
    }

    @Test func restoreSessionStaysSignedOutWhenStoreIsEmpty() async {
        let session = makeSession()
        await session.restoreSession()

        #expect(session.status == .signedOut)
        #expect(session.identity == nil)
        #expect(store.loadCalls == 1)
    }

    @Test func restoreSessionReadsStoreOnlyOnce() async throws {
        try store.save(freshTokens())
        let session = makeSession()

        await session.restoreSession()
        await session.restoreSession()

        #expect(session.status == .signedIn)
        #expect(store.loadCalls == 1)
    }

    @Test func restoreSessionReturnsToSignedOutWhenLoadFails() async {
        store.failLoading()
        let session = makeSession()

        await session.restoreSession()

        #expect(session.status == .signedOut)
        #expect(session.identity == nil)
        #expect(store.loadCalls == 1)
    }

    @Test func restoreSessionDoesNotOverwriteANewerSignIn() async throws {
        let suspendedStore = SuspendedLoadTokenStore(loadResult: nil)
        let session = AuthSession(
            configuration: AuthTestSupport.configuration,
            provider: provider,
            tokenStore: suspendedStore)
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(
                    accessToken: "access-2",
                    expiresIn: 3600,
                    refreshToken: "refresh-2",
                    idToken: AuthTestSupport.idToken(
                        subject: "user-2", email: "new@arcbox.dev", nonce: "nonce-1")))
        }

        let restoration = Task { await session.restoreSession() }
        await suspendedStore.waitUntilLoadStarts()
        let duplicateRestoration = Task { await session.restoreSession() }
        #expect(session.status == .restoring)
        #expect(await suspendedStore.loadCalls == 1)

        try await session.completeSignIn(
            callbackURL: callback(),
            expectedState: "state-1",
            verifier: "verifier",
            nonce: "nonce-1",
            endpoints: AuthTestSupport.endpoints)
        await suspendedStore.resumeLoad()
        await restoration.value
        await duplicateRestoration.value

        #expect(session.status == .signedIn)
        #expect(session.identity?.subject == "user-2")
        #expect(session.identity?.email == "new@arcbox.dev")
    }

    @Test func restoreSessionDoesNotReadStoreAfterSignIn() async throws {
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(
                    accessToken: "access-2",
                    expiresIn: 3600,
                    refreshToken: "refresh-2",
                    idToken: AuthTestSupport.idToken(
                        subject: "user-2", email: "new@arcbox.dev", nonce: "nonce-1")))
        }
        let session = makeSession()
        try await session.completeSignIn(
            callbackURL: callback(),
            expectedState: "state-1",
            verifier: "verifier",
            nonce: "nonce-1",
            endpoints: AuthTestSupport.endpoints)

        try store.save(freshTokens())
        await session.restoreSession()

        #expect(store.loadCalls == 0)
        #expect(session.status == .signedIn)
        #expect(session.identity?.subject == "user-2")
        #expect(session.identity?.email == "new@arcbox.dev")
    }

    // MARK: - completeSignIn

    private func callback(code: String = "code-1", state: String = "state-1") -> URL {
        URL(string: "com.arcboxlabs.desktop:/oauth2redirect?code=\(code)&state=\(state)")!
    }

    @Test func completeSignInHappyPath() async throws {
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(
                    accessToken: "access-1",
                    expiresIn: 3600,
                    refreshToken: "refresh-1",
                    idToken: AuthTestSupport.idToken(
                        subject: "user-1", email: "april@arcbox.dev", nonce: "nonce-1")))
        }
        let session = makeSession()
        try await session.completeSignIn(
            callbackURL: callback(),
            expectedState: "state-1",
            verifier: "verifier",
            nonce: "nonce-1",
            endpoints: AuthTestSupport.endpoints)
        #expect(session.status == .signedIn)
        #expect(session.identity?.email == "april@arcbox.dev")
        #expect(store.stored?.accessToken == "access-1")
        #expect(provider.exchangeCalls == 1)
    }

    @Test func completeSignInRejectsStateMismatch() async {
        let session = makeSession()
        await #expect(throws: OIDCError.stateMismatch) {
            try await session.completeSignIn(
                callbackURL: callback(state: "attacker-state"),
                expectedState: "state-1",
                verifier: "verifier",
                nonce: "nonce-1",
                endpoints: AuthTestSupport.endpoints)
        }
        #expect(session.status != .signedIn)
        #expect(store.stored == nil)
        #expect(provider.exchangeCalls == 0)
    }

    @Test func completeSignInSurfacesProviderError() async {
        let session = makeSession()
        let url = URL(
            string: "com.arcboxlabs.desktop:/oauth2redirect?error=access_denied&error_description=Denied&state=state-1"
        )!
        await #expect(throws: OIDCError.authorizationDenied("Denied")) {
            try await session.completeSignIn(
                callbackURL: url,
                expectedState: "state-1",
                verifier: "verifier",
                nonce: "nonce-1",
                endpoints: AuthTestSupport.endpoints)
        }
    }

    @Test func completeSignInRejectsNonceMismatch() async {
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(
                    accessToken: "access-1",
                    idToken: AuthTestSupport.idToken(subject: "user-1", nonce: "other-nonce")))
        }
        let session = makeSession()
        await #expect(throws: OIDCError.invalidIDToken) {
            try await session.completeSignIn(
                callbackURL: callback(),
                expectedState: "state-1",
                verifier: "verifier",
                nonce: "nonce-1",
                endpoints: AuthTestSupport.endpoints)
        }
        #expect(store.stored == nil)
    }

    // MARK: - UserInfo

    @Test func loadUserInfoPopulatesIdentity() async throws {
        try store.save(freshTokens())
        provider.configure {
            $0.userInfoResult = .success(
                OIDCUserInfo(
                    subject: "user-1",
                    name: "April",
                    email: "april@arcbox.dev",
                    emailVerified: true,
                    picture: URL(string: "https://avatars.example.com/user-1.png")))
        }
        let session = await makeRestoredSession()
        await session.loadUserInfo()
        #expect(provider.userInfoCalls == 1)
        #expect(session.identity?.name == "April")
        #expect(session.identity?.email == "april@arcbox.dev")
        #expect(session.identity?.emailVerified == true)
        #expect(session.identity?.avatarURL?.absoluteString == "https://avatars.example.com/user-1.png")
    }

    @Test func loadUserInfoKeepsIdentityOnFailure() async throws {
        try store.save(freshTokens())
        let session = await makeRestoredSession()
        let before = session.identity
        await session.loadUserInfo()
        #expect(provider.userInfoCalls == 1)
        #expect(session.identity == before)
        #expect(session.status == .signedIn)
    }

    @Test func loadUserInfoIsNoOpWhenSignedOut() async {
        let session = makeSession()
        await session.loadUserInfo()
        #expect(provider.userInfoCalls == 0)
    }

    @Test func signInFetchesUserInfo() async throws {
        let session = makeSession()
        _ = try await session.beginAuthorization()
        let pending = try #require(session.pendingAuthorization)
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(
                    accessToken: "access-1",
                    expiresIn: 3600,
                    idToken: AuthTestSupport.idToken(subject: "user-1", nonce: pending.nonce)))
            $0.userInfoResult = .success(
                OIDCUserInfo(
                    subject: "user-1",
                    name: "April",
                    picture: URL(string: "https://avatars.example.com/user-1.png")))
        }
        await session.handleAuthorizationCallback(callback(state: pending.state))
        #expect(session.status == .signedIn)
        #expect(provider.userInfoCalls == 1)
        #expect(session.identity?.name == "April")
        #expect(session.identity?.avatarURL != nil)
    }

    // MARK: - Deep-link callback

    @Test func deepLinkCallbackCompletesPendingSignIn() async throws {
        let session = makeSession()
        _ = try await session.beginAuthorization()
        let pending = try #require(session.pendingAuthorization)
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(
                    accessToken: "access-1",
                    expiresIn: 3600,
                    refreshToken: "refresh-1",
                    idToken: AuthTestSupport.idToken(
                        subject: "user-1", email: "april@arcbox.dev", nonce: pending.nonce)))
        }
        let handled = await session.handleAuthorizationCallback(callback(state: pending.state))
        #expect(handled)
        #expect(session.status == .signedIn)
        #expect(session.pendingAuthorization == nil)
        #expect(store.stored?.accessToken == "access-1")
    }

    @Test func deepLinkCallbackIgnoresForeignURLs() async {
        let session = makeSession()
        _ = try? await session.beginAuthorization()
        let handled = await session.handleAuthorizationCallback(
            URL(string: "arcbox://containers/abc")!)
        #expect(!handled)
        #expect(session.pendingAuthorization != nil)
        #expect(provider.exchangeCalls == 0)
    }

    @Test func deepLinkCallbackWithoutPendingSignInIsDropped() async {
        let session = makeSession()
        let handled = await session.handleAuthorizationCallback(callback())
        #expect(handled)
        #expect(session.status == .signedOut)
        #expect(provider.exchangeCalls == 0)
    }

    @Test func deepLinkCallbackRejectsStateMismatch() async throws {
        let session = makeSession()
        _ = try await session.beginAuthorization()
        let handled = await session.handleAuthorizationCallback(
            callback(state: "attacker-state"))
        #expect(handled)
        #expect(session.status == .error(OIDCError.stateMismatch.userMessage))
        #expect(session.pendingAuthorization == nil)
        #expect(store.stored == nil)
        #expect(provider.exchangeCalls == 0)
    }

    @Test func deepLinkCallbackConsumesPendingExactlyOnce() async throws {
        let session = makeSession()
        _ = try await session.beginAuthorization()
        let pending = try #require(session.pendingAuthorization)
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(
                    accessToken: "access-1",
                    expiresIn: 3600,
                    idToken: AuthTestSupport.idToken(subject: "user-1", nonce: pending.nonce)))
        }
        let url = callback(state: pending.state)
        let first = await session.handleAuthorizationCallback(url)
        let second = await session.handleAuthorizationCallback(url)
        #expect(first)
        #expect(second)
        #expect(session.status == .signedIn)
        #expect(provider.exchangeCalls == 1)
    }

    // MARK: - accessToken

    @Test func accessTokenThrowsWhenSignedOut() async {
        let session = makeSession()
        await #expect(throws: OIDCError.notSignedIn) {
            try await session.accessToken()
        }
    }

    @Test func accessTokenReturnsCachedTokenWhileFresh() async throws {
        try store.save(freshTokens())
        let session = await makeRestoredSession()
        #expect(try await session.accessToken() == "access-1")
        #expect(provider.refreshCalls == 0)
    }

    @Test func accessTokenRefreshesWhenExpired() async throws {
        try store.save(expiredTokens())
        provider.configure {
            $0.refreshResult = .success(
                TokenResponse(accessToken: "access-2", expiresIn: 3600, refreshToken: "refresh-2"))
        }
        let session = await makeRestoredSession()
        #expect(try await session.accessToken() == "access-2")
        #expect(provider.refreshCalls == 1)
        #expect(store.stored?.accessToken == "access-2")
        #expect(store.stored?.refreshToken == "refresh-2")
    }

    @Test func refreshKeepsOldRefreshTokenWhenNotRotated() async throws {
        try store.save(expiredTokens())
        provider.configure {
            $0.refreshResult = .success(TokenResponse(accessToken: "access-2", expiresIn: 3600))
        }
        let session = await makeRestoredSession()
        _ = try await session.accessToken()
        #expect(store.stored?.refreshToken == "refresh-1")
    }

    @Test func concurrentCallersTriggerExactlyOneRefresh() async throws {
        try store.save(expiredTokens())
        provider.configure {
            $0.refreshResult = .success(TokenResponse(accessToken: "access-2", expiresIn: 3600))
            $0.refreshDelay = .milliseconds(50)
        }
        let session = await makeRestoredSession()
        async let first = session.accessToken()
        async let second = session.accessToken()
        let tokens = try await (first, second)
        #expect(tokens == ("access-2", "access-2"))
        #expect(provider.refreshCalls == 1)
    }

    @Test func accessTokenThrowsWithoutRefreshToken() async throws {
        try store.save(expiredTokens(refreshToken: nil))
        let session = await makeRestoredSession()
        await #expect(throws: OIDCError.missingRefreshToken) {
            try await session.accessToken()
        }
    }

    @Test func invalidGrantEndsTheSession() async throws {
        try store.save(expiredTokens())
        provider.configure {
            $0.refreshResult = .failure(
                .tokenRequestFailed(status: 400, body: #"{"error":"invalid_grant"}"#))
        }
        let session = await makeRestoredSession()
        await #expect(throws: OIDCError.notSignedIn) {
            try await session.accessToken()
        }
        #expect(session.status == .signedOut)
        #expect(store.stored == nil)
    }

    @Test func transientRefreshFailureKeepsTheSession() async throws {
        try store.save(expiredTokens())
        provider.configure {
            $0.refreshResult = .failure(.network("timeout"))
        }
        let session = await makeRestoredSession()
        await #expect(throws: OIDCError.network("timeout")) {
            try await session.accessToken()
        }
        #expect(session.status == .signedIn)
        #expect(store.stored != nil)
    }

    // MARK: - signOut

    @Test func signOutRevokesAndClears() async throws {
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(accessToken: "access-1", expiresIn: 3600, refreshToken: "refresh-1"))
        }
        let session = makeSession()
        // Complete a sign-in so discovery has run and revocation is attempted.
        try await session.completeSignIn(
            callbackURL: callback(),
            expectedState: "state-1",
            verifier: "verifier",
            nonce: "nonce-1",
            endpoints: session.resolvedEndpoints())
        await session.signOut()
        #expect(session.status == .signedOut)
        #expect(session.identity == nil)
        #expect(store.stored == nil)
        #expect(provider.revokeCalls == 1)
    }

    @Test func signOutClearsEvenWhenRevocationFails() async throws {
        provider.configure {
            $0.exchangeResult = .success(
                TokenResponse(accessToken: "access-1", expiresIn: 3600, refreshToken: "refresh-1"))
            $0.revokeError = .network("unreachable")
        }
        let session = makeSession()
        try await session.completeSignIn(
            callbackURL: callback(),
            expectedState: "state-1",
            verifier: "verifier",
            nonce: "nonce-1",
            endpoints: session.resolvedEndpoints())
        await session.signOut()
        #expect(session.status == .signedOut)
        #expect(store.stored == nil)
        #expect(provider.revokeCalls == 1)
    }

    @Test func signOutWithoutDiscoverySkipsRevocation() async throws {
        try store.save(freshTokens())
        let session = await makeRestoredSession()
        await session.signOut()
        #expect(session.status == .signedOut)
        #expect(store.stored == nil)
        #expect(provider.revokeCalls == 0)
    }
}
