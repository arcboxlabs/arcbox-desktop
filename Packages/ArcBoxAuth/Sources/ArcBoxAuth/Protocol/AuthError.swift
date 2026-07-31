import Foundation

public enum AuthError: Error, Sendable, Equatable {
    /// The build carries the placeholder configuration; sign-in cannot work.
    case notConfigured
    /// The user rejected the device authorization in the browser.
    case authorizationDenied
    /// The device code expired before the browser approval completed.
    case deviceCodeExpired
    /// The provider answered with an unexpected status. `body` is truncated
    /// so raw provider responses never flood logs or the UI.
    case requestFailed(status: Int, body: String)
    case malformedResponse(String)
    case notSignedIn
    /// Transport-level failure, carried as a description to stay Equatable.
    case network(String)

    /// Short message suitable for the Account UI.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            "No sign-in service is configured for this build. See Local.xcconfig.example."
        case .authorizationDenied:
            "Sign-in was denied in the browser."
        case .deviceCodeExpired:
            "The sign-in request expired before it was approved. Please try again."
        case .requestFailed:
            "Sign-in failed while contacting the ArcBox account service. Please try again."
        case .malformedResponse:
            "The ArcBox account service sent an unexpected response."
        case .notSignedIn:
            "Your session has expired. Please sign in again."
        case .network(let description):
            "Network error: \(description)"
        }
    }
}
