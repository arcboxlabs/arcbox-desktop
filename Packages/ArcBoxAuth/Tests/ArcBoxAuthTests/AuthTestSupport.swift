import Foundation
import os

@testable import ArcBoxAuth

enum AuthTestSupport {
    static let configuration = OIDCClientConfiguration(
        issuerURL: URL(string: "https://idp.example.com")!,
        clientID: "test-client"
    )

    static let endpoints = OIDCEndpoints(
        authorizationEndpoint: URL(string: "https://idp.example.com/auth")!,
        tokenEndpoint: URL(string: "https://idp.example.com/token")!,
        revocationEndpoint: URL(string: "https://idp.example.com/revoke")!,
        userinfoEndpoint: URL(string: "https://idp.example.com/userinfo")!
    )

    /// Unsigned JWT with the given payload, shaped like a real ID token.
    static func idToken(subject: String, email: String? = nil, nonce: String? = nil) -> String {
        var claims = ["\"sub\":\"\(subject)\"", "\"exp\":4102444800"]
        if let email { claims.append("\"email\":\"\(email)\"") }
        if let nonce { claims.append("\"nonce\":\"\(nonce)\"") }
        let header = Data("{\"alg\":\"RS256\"}".utf8).base64URLEncodedString()
        let payload = Data("{\(claims.joined(separator: ","))}".utf8).base64URLEncodedString()
        return "\(header).\(payload).signature"
    }
}

final class InMemoryTokenStore: TokenStoring {
    private struct State {
        var stored: StoredTokens?
        var saveCalls = 0
        var loadCalls = 0
        var clearCalls = 0
        var shouldFailLoading = false
    }

    enum Failure: Error {
        case loadFailed
    }

    private let storage: OSAllocatedUnfairLock<State>

    var stored: StoredTokens? { storage.withLock { $0.stored } }
    var saveCalls: Int { storage.withLock { $0.saveCalls } }
    var loadCalls: Int { storage.withLock { $0.loadCalls } }
    var clearCalls: Int { storage.withLock { $0.clearCalls } }

    init(initial: StoredTokens? = nil) {
        storage = OSAllocatedUnfairLock(initialState: State(stored: initial))
    }

    func failLoading() {
        storage.withLock { $0.shouldFailLoading = true }
    }

    func save(_ tokens: StoredTokens) throws {
        storage.withLock {
            $0.saveCalls += 1
            $0.stored = tokens
        }
    }

    func load() throws -> StoredTokens? {
        let result = storage.withLock {
            $0.loadCalls += 1
            return ($0.shouldFailLoading, $0.stored)
        }
        if result.0 { throw Failure.loadFailed }
        return result.1
    }

    func clear() throws {
        storage.withLock {
            $0.clearCalls += 1
            $0.stored = nil
        }
    }
}

actor SuspendedLoadTokenStore: TokenStoring {
    private let loadResult: StoredTokens?
    private var stored: StoredTokens?
    private var loadContinuation: CheckedContinuation<StoredTokens?, Never>?
    private var hasStartedLoading = false
    private(set) var loadCalls = 0

    init(loadResult: StoredTokens?) {
        self.loadResult = loadResult
        stored = loadResult
    }

    func save(_ tokens: StoredTokens) {
        stored = tokens
    }

    func load() async -> StoredTokens? {
        loadCalls += 1
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
            hasStartedLoading = true
        }
    }

    func clear() {
        stored = nil
    }

    func waitUntilLoadStarts() async {
        while !hasStartedLoading {
            await Task.yield()
        }
    }

    func resumeLoad() {
        loadContinuation?.resume(returning: loadResult)
        loadContinuation = nil
    }
}

final class FakeOIDCProvider: OIDCProviding {
    struct State {
        var exchangeResult: Result<TokenResponse, OIDCError> = .failure(.notSignedIn)
        var refreshResult: Result<TokenResponse, OIDCError> = .failure(.notSignedIn)
        var userInfoResult: Result<OIDCUserInfo, OIDCError> = .failure(
            .userInfoFailed(status: 401, body: "unconfigured"))
        var refreshDelay: Duration?
        var revokeError: OIDCError?
        var exchangeCalls = 0
        var refreshCalls = 0
        var revokeCalls = 0
        var userInfoCalls = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var exchangeCalls: Int { state.withLock { $0.exchangeCalls } }
    var refreshCalls: Int { state.withLock { $0.refreshCalls } }
    var revokeCalls: Int { state.withLock { $0.revokeCalls } }
    var userInfoCalls: Int { state.withLock { $0.userInfoCalls } }

    func configure(_ change: @Sendable (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func discover(issuer: URL) async throws -> OIDCEndpoints {
        AuthTestSupport.endpoints
    }

    func exchangeCode(
        _ code: String,
        verifier: String,
        configuration: OIDCClientConfiguration,
        endpoints: OIDCEndpoints
    ) async throws -> TokenResponse {
        try state.withLock { s in
            s.exchangeCalls += 1
            return s.exchangeResult
        }.get()
    }

    func refresh(
        refreshToken: String,
        configuration: OIDCClientConfiguration,
        endpoints: OIDCEndpoints
    ) async throws -> TokenResponse {
        let (delay, result) = state.withLock { s in
            s.refreshCalls += 1
            return (s.refreshDelay, s.refreshResult)
        }
        if let delay { try await Task.sleep(for: delay) }
        return try result.get()
    }

    func revoke(
        token: String,
        tokenTypeHint: String,
        configuration: OIDCClientConfiguration,
        endpoint: URL
    ) async throws {
        let error = state.withLock { s in
            s.revokeCalls += 1
            return s.revokeError
        }
        if let error { throw error }
    }

    func userInfo(accessToken: String, endpoint: URL) async throws -> OIDCUserInfo {
        try state.withLock { s in
            s.userInfoCalls += 1
            return s.userInfoResult
        }.get()
    }
}
