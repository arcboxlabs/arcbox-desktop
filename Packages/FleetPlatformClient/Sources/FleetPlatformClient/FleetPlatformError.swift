import Foundation

/// Stable errors from the ArcBox Platform REST boundary.
public enum FleetPlatformError: Error, Sendable, Equatable {
    case authenticationRequired
    case forbidden
    case notFound
    case conflict
    case rateLimited
    case serverError(statusCode: Int)
    case api(statusCode: Int)
    case invalidResponse
    case malformedResponse
    case transport(code: URLError.Code)
}

extension FleetPlatformError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "The ArcBox Platform did not accept the current sign-in session."
        case .forbidden:
            "You do not have access to this ArcBox workspace."
        case .notFound:
            "The requested ArcBox Platform resource was not found."
        case .conflict:
            "The ArcBox Platform could not complete the request because the resource changed."
        case .rateLimited:
            "The ArcBox Platform is receiving too many requests. Try again later."
        case .serverError(let statusCode):
            "The ArcBox Platform is unavailable (HTTP \(statusCode))."
        case .api(let statusCode):
            "The ArcBox Platform request failed (HTTP \(statusCode))."
        case .invalidResponse:
            "The ArcBox Platform returned a non-HTTP response."
        case .malformedResponse:
            "The ArcBox Platform returned an unreadable response."
        case .transport(let code):
            "Could not reach the ArcBox Platform (\(code.rawValue))."
        }
    }
}
