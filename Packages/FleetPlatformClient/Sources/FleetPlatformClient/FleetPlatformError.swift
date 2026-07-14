import Foundation

/// Stable errors from the ArcBox Platform REST boundary.
public enum FleetPlatformError: Error, Sendable, Equatable {
    case unauthenticated
    case forbidden
    case notFound
    case api(statusCode: Int, status: String?, message: String)
    case invalidResponse
    case malformedResponse
}

extension FleetPlatformError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            "The ArcBox Platform did not accept the current sign-in session."
        case .forbidden:
            "You do not have access to this ArcBox workspace."
        case .notFound:
            "The requested ArcBox Platform resource was not found."
        case .api(_, _, let message):
            message
        case .invalidResponse:
            "The ArcBox Platform returned a non-HTTP response."
        case .malformedResponse:
            "The ArcBox Platform returned an unreadable response."
        }
    }
}
