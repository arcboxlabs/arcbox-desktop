import ArcBoxClient
@preconcurrency import Sentry

/// Centralized error capture with automatic classification and consistent tagging.
///
/// Wraps SentrySDK.capture with standardized domain/operation/category tags so
/// every error reaching Sentry has the same shape. Also bridges errors to
/// PostHog (via ``Analytics``) for product-level error rate tracking.
///
/// Cancellation is not an error. A view disappearing, a daemon restart or the
/// app quitting cancels whatever call was in flight, and that arrives as
/// `CancellationError` or as the `RPCError` grpc-swift wraps one in
/// (`Error/isCancellation`). ``send(_:tags:)`` drops those before either
/// backend sees them. Call sites keep their own cancellation handling keyed
/// on the task, not on the error's shape: a cancellation the transport
/// manufactured while the task is alive is a failure the UI should show.
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
        let sent = send(
            error,
            tags: [
                "error_domain": domain.rawValue,
                "operation": operation,
                "error_category": category.rawValue,
            ])
        guard sent else { return }

        // Bridge to PostHog for product-level error rate tracking.
        Analytics.capture(
            .errorOccurred,
            properties: [
                "domain": domain.rawValue,
                "operation": operation,
                "category": category.rawValue,
            ])
    }

    /// Hand `error` to Sentry under `tags`.
    ///
    /// The one path to `SentrySDK.capture(error:)`, shared by the app's own
    /// captures and by ``SentryDiagnosticsSink``, so the cancellation guard
    /// lives here once. Returns `false` when the error was dropped as
    /// cancellation; `true` means Sentry was handed the event, which is a
    /// no-op while Sentry is not initialized.
    @discardableResult
    static func send(_ error: Error, tags: [String: String]) -> Bool {
        guard !error.isCancellation else { return false }

        SentrySDK.capture(error: error) { scope in
            for (key, value) in tags {
                scope.setTag(value: value, key: key)
            }
        }
        return true
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
        case machine
        case sandbox
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
        case unknown
    }

    /// Classify an error by inspecting its description for well-known gRPC /
    /// transport patterns.  This intentionally duplicates the heuristics in
    /// `ArcBoxClient.userMessage(for:)` so the classification stays close to
    /// the capture site without pulling in the client package.
    static func classify(_ error: Error) -> ErrorCategory {
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

// MARK: - ArcBoxClient Bridge

/// Sends ``ArcBoxClient``'s diagnostics to Sentry.
///
/// The client package emits breadcrumbs and errors but deliberately links no
/// crash reporter — a gRPC client has no business owning one, and depending on
/// Sentry there dragged its binary artifacts into every protobuf regeneration.
/// ``AppDelegate/initSentry()`` installs this once Sentry is up.
///
/// `nonisolated` because the client calls it from wherever it happens to be —
/// this target defaults to `MainActor` isolation.
nonisolated struct SentryDiagnosticsSink: DiagnosticsSink {
    func add(_ breadcrumb: DiagnosticBreadcrumb) {
        let crumb = Breadcrumb(level: breadcrumb.level.sentryLevel, category: breadcrumb.category)
        crumb.message = breadcrumb.message
        SentrySDK.addBreadcrumb(crumb)
    }

    func capture(_ error: Error, tags: [String: String]) {
        ErrorReporting.send(error, tags: tags)
    }
}

extension DiagnosticBreadcrumb.Level {
    nonisolated fileprivate var sentryLevel: SentryLevel {
        switch self {
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}
