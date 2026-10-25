import Foundation
import Testing

@testable import ArcBoxAuth

struct AuthClientConfigurationTests {
    @Test func resolvesAConfiguredIssuerAndClient() throws {
        let configuration = try #require(
            AuthClientConfiguration.resolve(
                issuer: "https://auth.example.com/api/auth", clientID: "desktop"))

        #expect(configuration.issuerURL.absoluteString == "https://auth.example.com/api/auth")
        #expect(configuration.clientID == "desktop")
        #expect(!configuration.isPlaceholder)
    }

    @Test func derivesEndpointsFromTheIssuer() throws {
        let configuration = try #require(
            AuthClientConfiguration.resolve(
                issuer: "https://auth.example.com/api/auth", clientID: "desktop"))

        #expect(
            configuration.deviceCodeEndpoint.absoluteString
                == "https://auth.example.com/api/auth/device/code")
        #expect(
            configuration.deviceTokenEndpoint.absoluteString
                == "https://auth.example.com/api/auth/device/token")
        #expect(
            configuration.sessionEndpoint.absoluteString
                == "https://auth.example.com/api/auth/get-session")
        #expect(
            configuration.signOutEndpoint.absoluteString
                == "https://auth.example.com/api/auth/sign-out")
    }

    @Test(arguments: [nil, "", "$(OIDC_ISSUER_URL)", "YOUR_OIDC_ISSUER_URL_HERE"])
    func treatsUnexpandedOrPlaceholderIssuersAsUnconfigured(issuer: String?) {
        #expect(AuthClientConfiguration.resolve(issuer: issuer, clientID: "desktop") == nil)
    }

    @Test(arguments: [nil, "", "$(OIDC_CLIENT_ID)", "YOUR_OIDC_CLIENT_ID_HERE"])
    func treatsUnexpandedOrPlaceholderClientIDsAsUnconfigured(clientID: String?) {
        #expect(
            AuthClientConfiguration.resolve(issuer: "https://a.example.com", clientID: clientID)
                == nil)
    }

    @Test func labelsEnvironments() {
        #expect(AuthClientConfiguration.placeholder.environmentLabel == "Not Configured")
        #expect(
            AuthClientConfiguration.resolve(
                issuer: "http://localhost:2801/api/auth", clientID: "desktop")?
                .environmentLabel == "Local")
        #expect(
            AuthClientConfiguration.resolve(
                issuer: "https://auth.arcbox.dev/api/auth", clientID: "desktop")?
                .environmentLabel == "auth.arcbox.dev")
    }
}
