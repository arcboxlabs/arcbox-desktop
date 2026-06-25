import Foundation
import OSLog
import PostHog
@preconcurrency import Sentry

extension ArcBoxDesktopApp {
    /// Initialize Sentry crash reporting if a DSN is configured.
    /// DSN is read from Info.plist (injected via SENTRY_DSN build setting).
    /// No-ops gracefully when DSN is empty or placeholder.
    static func initSentry() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
            !dsn.isEmpty, dsn != "YOUR_SENTRY_DSN_HERE", dsn != "$(SENTRY_DSN)"
        else {
            Log.startup.info("Sentry DSN not configured, crash reporting disabled")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.enableAutoSessionTracking = true
            options.enableCrashHandler = true
            options.enableAutoPerformanceTracing = true
            options.tracesSampleRate = 0.2
            options.beforeSend = { event in
                // Scrub PII: remove user paths from breadcrumbs and exceptions.
                Self.scrubPII(event)
                return event
            }
            #if DEBUG
                options.debug = true
                options.environment = "development"
            #else
                options.environment = "production"
            #endif
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        SentrySDK.configureScope { scope in
            scope.setTag(value: "app", key: "process_type")
            scope.setTag(value: version, key: "app_version")
        }
        Log.startup.info("Sentry initialized")
    }

    /// Initialize PostHog product analytics if an API key is configured.
    /// API key is read from Info.plist (injected via POSTHOG_API_KEY build setting).
    /// No-ops gracefully when key is empty or placeholder.
    /// Telemetry is enabled by default; users can opt out in Settings > Privacy.
    static func initPostHog() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String,
            !apiKey.isEmpty, apiKey != "YOUR_POSTHOG_API_KEY_HERE", apiKey != "$(POSTHOG_API_KEY)"
        else {
            Log.startup.info("PostHog API key not configured, telemetry disabled")
            return
        }

        // Ensure UserDefaults default matches @AppStorage default (true).
        // Without this, bool(forKey:) returns false on first launch before
        // the Settings view has ever appeared.
        UserDefaults.standard.register(defaults: ["telemetryEnabled": true])

        let config = PostHogConfig(apiKey: apiKey, host: "https://us.i.posthog.com")
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false  // No-op on macOS, track manually
        config.personProfiles = .identifiedOnly
        config.optOut = !UserDefaults.standard.bool(forKey: "telemetryEnabled")
        #if DEBUG
            // Never send telemetry from development builds.
            config.optOut = true
        #endif
        PostHogSDK.shared.setup(config)
        Log.startup.info("PostHog initialized (opted \(config.optOut ? "out" : "in", privacy: .public))")
    }

    /// Strip home directory paths from Sentry events to avoid leaking usernames.
    private static func scrubPII(_ event: Event) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        guard !homeDir.isEmpty else { return }
        for breadcrumb in event.breadcrumbs ?? [] {
            if let msg = breadcrumb.message {
                breadcrumb.message = msg.replacingOccurrences(of: homeDir, with: "~")
            }
        }
    }
}
