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
        revocationEndpoint: URL(string: "https://idp.example.com/revoke")!
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
    private let storage = OSAllocatedUnfairLock<StoredTokens?>(initialState: nil)

    var stored: StoredTokens? { storage.withLock { $0 } }

    init(initial: StoredTokens? = nil) {
        storage.withLock { $0 = initial }
    }

    func save(_ tokens: StoredTokens) throws { storage.withLock { $0 = tokens } }
    func load() throws -> StoredTokens? { storage.withLock { $0 } }
    func clear() throws { storage.withLock { $0 = nil } }
}

final class FakeOIDCProvider: OIDCProviding {
    struct State {
        var exchangeResult: Result<TokenResponse, OIDCError> = .failure(.notSignedIn)
        var refreshResult: Result<TokenResponse, OIDCError> = .failure(.notSignedIn)
        var refreshDelay: Duration?
        var revokeError: OIDCError?
        var exchangeCalls = 0
        var refreshCalls = 0
        var revokeCalls = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var exchangeCalls: Int { state.withLock { $0.exchangeCalls } }
    var refreshCalls: Int { state.withLock { $0.refreshCalls } }
    var revokeCalls: Int { state.withLock { $0.revokeCalls } }

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
}
