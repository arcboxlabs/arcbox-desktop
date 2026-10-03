import Foundation
import Testing

@testable import ArcBoxAuth

@MainActor
struct AuthSessionTests {
    private let provider = FakeAuthProvider()
    private let store = InMemoryTokenStore()
    private let sleeper = RecordingSleeper()
    private let browser = BrowserSpy()

    private func makeSession(
        configuration: AuthClientConfiguration = AuthTestSupport.configuration,
        provider: (any AuthProviding)? = nil,
        tokenStore: (any TokenStoring)? = nil
    ) -> AuthSession {
        AuthSession(
            configuration: configuration,
            provider: provider ?? self.provider,
            tokenStore: tokenStore ?? store,
            sleeper: sleeper.sleep,
            openURL: browser.open
        )
    }

    private static let storedSession = StoredSession(
        sessionToken: "stored-token",
        expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
    )

    // MARK: - Sign-in

    @Test func signInStoresSessionAndLoadsIdentity() async throws {
        let session = makeSession()
        await session.signIn()

        #expect(session.status == .signedIn)
        #expect(try await session.accessToken() == "session-1")
        #expect(store.stored?.sessionToken == "session-1")
        #expect(session.identity?.subject == "user-1")
        #expect(session.identity?.name == "Ada")
        #expect(session.deviceAuthorization == nil)
        #expect(browser.opened == [AuthTestSupport.grant().verificationURIComplete!])
    }

    @Test func signInPollsUntilApproved() async {
        provider.configure { state in
            state.pollScript = [
                .success(.authorizationPending),
                .success(.authorizationPending),
                .success(.granted(DeviceTokenGrant(sessionToken: "session-1", expiresAt: nil))),
            ]
        }
        let session = makeSession()
        await session.signIn()

        #expect(session.status == .signedIn)
        #expect(provider.pollCalls == 3)
        #expect(sleeper.slept == [.seconds(5.0), .seconds(5.0), .seconds(5.0)])
    }

    @Test func slowDownStretchesThePollingInterval() async {
        provider.configure { state in
            state.pollScript = [
                .success(.slowDown),
                .success(.authorizationPending),
                .success(.granted(DeviceTokenGrant(sessionToken: "session-1", expiresAt: nil))),
            ]
        }
        let session = makeSession()
        await session.signIn()

        #expect(session.status == .signedIn)
        #expect(sleeper.slept == [.seconds(5.0), .seconds(10.0), .seconds(10.0)])
    }

    @Test func denialInTheBrowserFailsSignIn() async {
        provider.configure { state in
            state.pollScript = [.failure(.authorizationDenied)]
        }
        let session = makeSession()
        await session.signIn()

        #expect(session.status == .error(AuthError.authorizationDenied.userMessage))
        #expect(store.stored == nil)
    }

    @Test func deviceCodeExpiryFailsSignInLocally() async {
        provider.configure { state in
            state.deviceCodeResult = .success(AuthTestSupport.grant(expiresIn: 12))
            state.pollScript = [.success(.authorizationPending)]
        }
        let session = makeSession()
        await session.signIn()

        #expect(session.status == .error(AuthError.deviceCodeExpired.userMessage))
        // Two polls fit inside the 12s budget with a 5s interval.
        #expect(provider.pollCalls == 2)
    }

    @Test func cancelDuringPollingReturnsToSignedOut() async {
        provider.configure { state in
            state.pollScript = [.success(.authorizationPending)]
        }
        let session = makeSession()
        let signIn = Task { await session.signIn() }
        while provider.pollCalls == 0 {
            await Task.yield()
        }
        session.cancelSignIn()
        await signIn.value

        #expect(session.status == .signedOut)
        #expect(session.deviceAuthorization == nil)
        #expect(store.stored == nil)
    }

    @Test func cancellationAfterTokenGrantDoesNotRollBackTheCommittedSession() async throws {
        let gatedStore = GatedTokenStore()
        let session = makeSession(tokenStore: gatedStore)
        let signIn = Task { await session.signIn() }
        while await gatedStore.saveCalls == 0 {
            await Task.yield()
        }

        session.cancelSignIn()
        await gatedStore.releaseSave()
        await signIn.value

        #expect(session.status == .signedIn)
        #expect(try await session.accessToken() == "session-1")
        let stored = await gatedStore.stored
        #expect(stored?.sessionToken == "session-1")
    }

    @Test func placeholderConfigurationCannotSignIn() async {
        let session = makeSession(configuration: .placeholder)
        await session.signIn()

        #expect(session.status == .error(AuthError.notConfigured.userMessage))
        #expect(provider.deviceCodeCalls == 0)
    }

    @Test func signInWhileSigningInIsANoOp() async {
        provider.configure { state in
            state.pollScript = [.success(.authorizationPending)]
        }
        let session = makeSession()
        let first = Task { await session.signIn() }
        while provider.deviceCodeCalls == 0 {
            await Task.yield()
        }
        await session.signIn()
        #expect(provider.deviceCodeCalls == 1)

        session.cancelSignIn()
        await first.value
    }

    @Test func concurrentSignInStartsOnlyOneDeviceFlow() async {
        let session = makeSession()
        let first = Task { await session.signIn() }
        let second = Task { await session.signIn() }

        await first.value
        await second.value

        #expect(provider.deviceCodeCalls == 1)
        #expect(browser.opened.count == 1)
    }

    // MARK: - Restore

    @Test func restoreAdoptsAStoredSessionWithoutNetwork() async throws {
        try store.save(Self.storedSession)
        let session = makeSession()
        await session.restoreSession()

        #expect(session.status == .signedIn)
        #expect(try await session.accessToken() == "stored-token")
        #expect(provider.sessionCalls == 0)
    }

    @Test func restoreWithAnEmptyKeychainSignsOut() async {
        let session = makeSession()
        await session.restoreSession()
        #expect(session.status == .signedOut)
    }

    @Test func restoreFailureSignsOut() async {
        store.failLoading()
        let session = makeSession()
        await session.restoreSession()
        #expect(session.status == .signedOut)
    }

    // MARK: - Session refresh

    @Test func refreshPublishesIdentityAndSlidExpiry() async throws {
        try store.save(Self.storedSession)
        let session = makeSession()
        await session.restoreSession()
        await session.refreshSession()

        #expect(session.identity?.subject == "user-1")
        #expect(session.identity?.email == "ada@example.com")
        #expect(store.stored?.expiresAt == AuthTestSupport.snapshot().session.expiresAt)
    }

    @Test func refreshSignsOutWhenTheProviderDropsTheSession() async throws {
        try store.save(Self.storedSession)
        provider.configure { state in
            state.sessionResult = .success(nil)
        }
        let session = makeSession()
        await session.restoreSession()
        await session.refreshSession()

        #expect(session.status == .signedOut)
        #expect(store.stored == nil)
    }

    @Test func refreshKeepsTheSessionOnTransportFailure() async throws {
        try store.save(Self.storedSession)
        provider.configure { state in
            state.sessionResult = .failure(.network("offline"))
        }
        let session = makeSession()
        await session.restoreSession()
        await session.refreshSession()

        #expect(session.status == .signedIn)
        #expect(try await session.accessToken() == "stored-token")
    }

    @Test func staleRefreshCannotClearAReplacementSession() async throws {
        let gate = AuthAsyncGate()
        let provider = FakeAuthProvider(sessionGate: gate)
        provider.configure { state in
            state.sessionResult = .success(nil)
        }
        let store = InMemoryTokenStore(initial: Self.storedSession)
        let session = makeSession(provider: provider, tokenStore: store)
        await session.restoreSession()

        let refresh = Task { await session.refreshSession() }
        while provider.sessionCalls == 0 {
            await Task.yield()
        }
        let replacement = StoredSession(sessionToken: "replacement-token", expiresAt: nil)
        try store.save(replacement)
        session.adopt(replacement)
        await gate.open()
        await refresh.value

        #expect(session.status == .signedIn)
        #expect(try await session.accessToken() == "replacement-token")
        #expect(store.stored == replacement)
    }

    // MARK: - Sign-out

    @Test func signOutRevokesServerSideAndClearsLocally() async throws {
        try store.save(Self.storedSession)
        let session = makeSession()
        await session.restoreSession()
        await session.signOut()

        #expect(session.status == .signedOut)
        #expect(provider.signOutTokens == ["stored-token"])
        #expect(store.stored == nil)
        await #expect(throws: AuthError.notSignedIn) {
            try await session.accessToken()
        }
    }

    @Test func signOutClearsLocallyEvenWhenRevocationFails() async throws {
        try store.save(Self.storedSession)
        provider.configure { state in
            state.signOutError = .network("offline")
        }
        let session = makeSession()
        await session.restoreSession()
        await session.signOut()

        #expect(session.status == .signedOut)
        #expect(store.stored == nil)
    }

    @Test func accessTokenThrowsWhenSignedOut() async {
        let session = makeSession()
        await #expect(throws: AuthError.notSignedIn) {
            try await session.accessToken()
        }
    }
}
