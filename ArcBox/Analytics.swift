import PostHog
import os

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

    // MARK: - Identity

    /// Tie subsequent events to a signed-in platform account, keyed by the
    /// OIDC subject.  PostHog runs in `.identifiedOnly` mode, so a person
    /// profile exists only once this is called; users who never sign in stay
    /// anonymous.
    static func identify(_ distinctID: String, properties: [String: Any] = [:]) {
        PostHogSDK.shared.identify(distinctID, userProperties: properties)
    }

    /// Drop the current identity and mint a fresh anonymous ID.  Required on
    /// sign-out, otherwise the next account to use this Mac is merged into the
    /// previous person profile.
    static func reset() {
        PostHogSDK.shared.reset()
        // `reset()` also wipes the registered super properties, which describe
        // the install rather than the person — put them straight back.
        superProperties.withLockUnchecked { properties in
            guard !properties.isEmpty else { return }
            PostHogSDK.shared.register(properties)
        }
    }

    /// Apply the Settings > Privacy toggle.  While opted out the SDK drops
    /// every call, including `identify`.
    static func optIn() {
        PostHogSDK.shared.optIn()
    }

    static func optOut() {
        PostHogSDK.shared.optOut()
    }

    // MARK: - Super Properties

    /// Mirrors what has been registered so `reset()` can restore it.  The
    /// `unchecked` variants are used only because `[String: Any]` is not
    /// `Sendable`; mutual exclusion is what makes the access safe.
    private static let superProperties = OSAllocatedUnfairLock<[String: Any]>(uncheckedState: [:])

    /// Attach properties to every subsequent event.  Used for the handful of
    /// slow-moving dimensions worth segmenting the whole dataset by; the SDK
    /// already supplies `$app_version`, `$os_version`, and `$device_type`.
    static func register(_ properties: [String: Any]) {
        superProperties.withLockUnchecked { $0.merge(properties) { _, new in new } }
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
