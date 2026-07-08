import Foundation

public enum OIDCAuthorizationURLBuilder {
    public static func makeURL(
        endpoints: OIDCEndpoints,
        configuration: OIDCClientConfiguration,
        pkce: PKCECodePair,
        state: String,
        nonce: String
    ) throws -> URL {
        guard
            var components = URLComponents(
                url: endpoints.authorizationEndpoint, resolvingAgainstBaseURL: false)
        else {
            throw OIDCError.invalidAuthorizationEndpoint
        }
        var query = components.queryItems ?? []
        query.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: OIDCClientConfiguration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: OIDCClientConfiguration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ])
        components.queryItems = query
        guard let url = components.url else {
            throw OIDCError.invalidAuthorizationEndpoint
        }
        return url
    }
}
