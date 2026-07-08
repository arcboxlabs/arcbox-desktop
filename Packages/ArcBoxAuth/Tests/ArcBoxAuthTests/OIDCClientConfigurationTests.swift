import Foundation
import Testing

@testable import ArcBoxAuth

struct OIDCClientConfigurationTests {
    @Test func resolvesConfiguredValues() throws {
        let config = try #require(
            OIDCClientConfiguration.resolve(
                issuer: "https://auth.arcbox.dev", clientID: "arcbox-desktop"))
        #expect(config.issuerURL == URL(string: "https://auth.arcbox.dev"))
        #expect(config.clientID == "arcbox-desktop")
        #expect(!config.isPlaceholder)
    }

    @Test(
        arguments: [
            nil, "", "$(OIDC_ISSUER_URL)", "YOUR_OIDC_ISSUER_URL_HERE",
        ] as [String?])
    func rejectsUnconfiguredIssuer(_ issuer: String?) {
        #expect(OIDCClientConfiguration.resolve(issuer: issuer, clientID: "arcbox-desktop") == nil)
    }

    @Test(
        arguments: [
            nil, "", "$(OIDC_CLIENT_ID)", "YOUR_OIDC_CLIENT_ID_HERE",
        ] as [String?])
    func rejectsUnconfiguredClientID(_ clientID: String?) {
        #expect(
            OIDCClientConfiguration.resolve(issuer: "https://auth.arcbox.dev", clientID: clientID)
                == nil)
    }

    @Test func placeholderIsInert() {
        let placeholder = OIDCClientConfiguration.placeholder
        #expect(placeholder.isPlaceholder)
        #expect(placeholder.environmentLabel == "Not Configured")
        // RFC 2606 reserved TLD — guaranteed to never resolve.
        #expect(placeholder.issuerURL.host()?.hasSuffix(".invalid") == true)
    }

    @Test func environmentLabelDescribesTheHost() {
        let local = OIDCClientConfiguration(
            issuerURL: URL(string: "http://localhost:5556/dex")!, clientID: "arcbox-desktop")
        #expect(local.environmentLabel == "Local")
        let staging = OIDCClientConfiguration(
            issuerURL: URL(string: "https://auth.staging.arcbox.dev")!, clientID: "arcbox-desktop")
        #expect(staging.environmentLabel == "auth.staging.arcbox.dev")
    }
}
