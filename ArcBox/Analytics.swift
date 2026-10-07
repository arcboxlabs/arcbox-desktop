import Foundation
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
///
/// Conventions: lifecycle events fire only on success — failures are already
/// covered by `error_occurred` via `ErrorReporting`.  Properties carry
/// low-cardinality dimensions only; never IDs, names, image references, or
/// file paths.
nonisolated enum Analytics {

    /// Record an analytics event.  No-ops when PostHog is not configured.
    static func capture(_ event: Event, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    static let legacyIdentityKey = "analyticsIdentified"

    /// Reset a persisted account identity after SDK setup and before registering install properties.
    /// The marker survives launches; anonymous installs must keep their existing anonymous ID.
    @discardableResult
    static func resetLegacyIdentityIfNeeded(
        defaults: UserDefaults = .standard,
        reset: () -> Void = { PostHogSDK.shared.reset() }
    ) -> Bool {
        guard defaults.bool(forKey: legacyIdentityKey) else { return false }
        reset()
        defaults.removeObject(forKey: legacyIdentityKey)
        return true
    }

    /// Apply the Settings > Privacy toggle to product analytics.
    static func optIn() {
        PostHogSDK.shared.optIn()
    }

    static func optOut() {
        PostHogSDK.shared.optOut()
    }

    // MARK: - Super Properties

    /// Attach properties to every subsequent event.  Used for the handful of
    /// slow-moving dimensions worth segmenting the whole dataset by; the SDK
    /// already supplies `$app_version`, `$os_version`, and `$device_type`.
    static func register(_ properties: [String: Any]) {
        PostHogSDK.shared.register(properties)
    }

    // MARK: - Event Catalog

    enum Event: String {
        // Startup.  App open/install/update are captured by the SDK's
        // `captureApplicationLifecycleEvents`, so they are not repeated here.
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
