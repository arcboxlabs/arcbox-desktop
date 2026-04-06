import PostHog

/// Centralized product analytics event catalog.
///
/// Wraps PostHog capture calls behind a type-safe enum so event names are
/// defined in one place.  All calls no-op when PostHog is not initialized or
/// the user has opted out — the SDK handles this internally.
///
/// Usage:
/// ```swift
/// Analytics.capture(.containerStarted)
/// Analytics.capture(.startupCompleted, properties: ["duration_ms": 1200])
/// ```
nonisolated enum Analytics {

    /// Record an analytics event.  No-ops when PostHog is not configured.
    static func capture(_ event: Event, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    // MARK: - Event Catalog

    enum Event: String {
        // Startup
        case appLaunched = "app_launched"
        case startupCompleted = "startup_completed"
        case startupFailed = "startup_failed"

        // Container lifecycle
        case containerStarted = "container_started"
        case containerStopped = "container_stopped"
        case containerCreated = "container_created"
        case containerRemoved = "container_removed"

        // Image lifecycle
        case imagePulled = "image_pulled"
        case imageRemoved = "image_removed"

        // Kubernetes
        case k8sEnabled = "k8s_enabled"
        case k8sDisabled = "k8s_disabled"

        // Feature usage
        case terminalOpened = "terminal_opened"
        case settingsOpened = "settings_opened"
        case diagnosticExported = "diagnostic_exported"

        // Performance
        case perfSlowCall = "perf_slow_call"

        // Error (supplements Sentry, not replaces)
        case errorOccurred = "error_occurred"
    }
}
