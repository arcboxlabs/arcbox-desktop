import Foundation
import Testing

@testable import ArcBoxAuth

struct OIDCAuthorizationURLBuilderTests {
    private let endpoints = OIDCEndpoints(
        authorizationEndpoint: URL(string: "https://idp.example.com/auth?audience=api")!,
        tokenEndpoint: URL(string: "https://idp.example.com/token")!
    )
    private let configuration = OIDCClientConfiguration(
        issuerURL: URL(string: "https://idp.example.com")!,
        clientID: "test-client"
    )

    @Test func includesAllRequiredParameters() throws {
        let pkce = PKCE.generateCodePair()
        let url = try OIDCAuthorizationURLBuilder.makeURL(
            endpoints: endpoints,
            configuration: configuration,
            pkce: pkce,
            state: "the-state",
            nonce: "the-nonce"
        )
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(byName["response_type"] == "code")
        #expect(byName["client_id"] == "test-client")
        #expect(byName["redirect_uri"] == "arcbox://auth/callback")
        #expect(byName["scope"] == "openid profile email offline_access")
        #expect(byName["state"] == "the-state")
        #expect(byName["nonce"] == "the-nonce")
        #expect(byName["code_challenge"] == pkce.challenge)
        #expect(byName["code_challenge_method"] == "S256")
        // Query parameters already on the discovered endpoint survive.
        #expect(byName["audience"] == "api")
    }

    @Test func neverLeaksTheVerifierIntoTheURL() throws {
        let pkce = PKCE.generateCodePair()
        let url = try OIDCAuthorizationURLBuilder.makeURL(
            endpoints: endpoints,
            configuration: configuration,
            pkce: pkce,
            state: "s",
            nonce: "n"
        )
        #expect(!url.absoluteString.contains(pkce.verifier))
    }
}
