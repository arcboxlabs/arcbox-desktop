import Foundation

public enum OIDCError: Error, Sendable, Equatable {
    case discoveryFailed(String)
    case invalidAuthorizationEndpoint
    case invalidCallbackURL
    /// The provider redirected back with an `error` parameter.
    case authorizationDenied(String)
    /// The `state` echoed by the provider does not match what we sent (CSRF guard).
    case stateMismatch
    case missingAuthorizationCode
    case tokenRequestFailed(status: Int, body: String)
    case userInfoFailed(status: Int, body: String)
    case missingRefreshToken
    case invalidIDToken
    case notSignedIn
    /// Transport-level failure, carried as a description to stay Equatable.
    case network(String)

    /// Short message suitable for the Account UI.
    public var userMessage: String {
        switch self {
        case .discoveryFailed:
            "Could not reach the sign-in service. Check the OIDC issuer configuration."
        case .invalidAuthorizationEndpoint, .invalidCallbackURL, .missingAuthorizationCode:
            "Sign-in failed: the provider sent an unexpected response."
        case .authorizationDenied(let reason):
            "Sign-in was denied: \(reason)"
        case .stateMismatch, .invalidIDToken:
            "Sign-in failed a security check. Please try again."
        case .tokenRequestFailed:
            "Sign-in failed while exchanging credentials. Please try again."
        case .userInfoFailed:
            "Could not load your profile. Please try again."
        case .missingRefreshToken, .notSignedIn:
            "Your session has expired. Please sign in again."
        case .network(let description):
            "Network error: \(description)"
        }
    }
}
