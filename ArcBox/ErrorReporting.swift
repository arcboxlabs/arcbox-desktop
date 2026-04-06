@preconcurrency import Sentry

/// Centralized error capture with automatic classification and consistent tagging.
///
/// Wraps SentrySDK.capture with standardized domain/operation/category tags so
/// every error reaching Sentry has the same shape. Also bridges errors to
/// PostHog (via ``Analytics``) for product-level error rate tracking.
///
/// Usage:
/// ```swift
/// } catch {
///     Log.container.error("Failed to start: \(error, privacy: .private)")
///     ErrorReporting.capture(error, domain: .container, operation: "start")
/// }
/// ```
nonisolated enum ErrorReporting {

    /// Capture an error to Sentry with standardized tags.
    /// No-ops if Sentry is not initialized.
    static func capture(
        _ error: Error,
        domain: ErrorDomain,
        operation: String
    ) {
        let category = classify(error)

        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: domain.rawValue, key: "error_domain")
            scope.setTag(value: operation, key: "operation")
            scope.setTag(value: category.rawValue, key: "error_category")
        }

        // Bridge to PostHog for product-level error rate tracking.
        Analytics.capture(
            .errorOccurred,
            properties: [
                "domain": domain.rawValue,
                "operation": operation,
                "category": category.rawValue,
            ])
    }

    // MARK: - Error Domain

    /// The subsystem where the error originated.
    enum ErrorDomain: String {
        case container
        case image
        case volume
        case network
        case pod
        case service
        case kubernetes
        case daemon
        case grpc
        case startup
    }

    // MARK: - Error Category

    /// Coarse classification derived from the error description.
    /// Mirrors the string matching in ``ArcBoxClient.userMessage(for:)``.
    enum ErrorCategory: String {
        case network
        case auth
        case notFound
        case conflict
        case timeout
        case cancelled
        case unknown
    }

    /// Classify an error by inspecting its description for well-known gRPC /
    /// transport patterns.  This intentionally duplicates the heuristics in
    /// `ArcBoxClient.userMessage(for:)` so the classification stays close to
    /// the capture site without pulling in the client package.
    static func classify(_ error: Error) -> ErrorCategory {
        if error is CancellationError { return .cancelled }

        let desc = String(describing: error)

        if desc.contains("UNAVAILABLE") || desc.contains("unavailable")
            || desc.contains("ECONNREFUSED") || desc.contains("Connection refused")
        {
            return .network
        }
        if desc.contains("DEADLINE_EXCEEDED") || desc.contains("deadline")
            || desc.contains("timed out")
        {
            return .timeout
        }
        if desc.contains("NOT_FOUND") || desc.contains("not found") {
            return .notFound
        }
        if desc.contains("ALREADY_EXISTS") || desc.contains("already exists") {
            return .conflict
        }
        if desc.contains("PERMISSION_DENIED") || desc.contains("permission") {
            return .auth
        }

        return .unknown
    }
}
