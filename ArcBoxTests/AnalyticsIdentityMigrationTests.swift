import AppKit
import Foundation
import PostHog
import Synchronization
import XCTest

@testable import ArcBox

@MainActor
final class AnalyticsIdentityMigrationTests: XCTestCase {
    func testStartupMigratesOnlyAccountIdentitiesAndHonorsTelemetryPreference() throws {
        // The SDK stores lifecycle versions globally even when its event storage uses an isolated API key.
        let lifecycleKeys = ["PHGVersionKey", "PHGBuildKeyV2"]
        let previousVersions = lifecycleKeys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(lifecycleKeys, previousVersions) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }

        for identified in [true, false] {
            for telemetryEnabled in [true, false] {
                try verifyStartup(identified: identified, telemetryEnabled: telemetryEnabled)
            }
        }
    }

    private func verifyStartup(identified: Bool, telemetryEnabled: Bool) throws {
        let suiteName = "AnalyticsIdentityMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let storage = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        .appendingPathComponent(bundleID).appendingPathComponent(suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            do {
                try FileManager.default.removeItem(at: storage)
            } catch {
                XCTFail("Failed to remove isolated analytics storage: \(error)")
            }
        }
        defaults.set(telemetryEnabled, forKey: "telemetryEnabled")
        defaults.set(identified, forKey: Analytics.legacyIdentityKey)

        let events = Mutex<[CapturedAnalyticsEvent]>([])
        let config = PostHogConfig(apiKey: suiteName, host: "https://posthog.invalid")
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [AnalyticsNetworkBlocker.self]
        config.urlSessionConfiguration = session
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.preloadFeatureFlags = false
        config.setBeforeSend { event in
            events.withLock {
                $0.append(
                    CapturedAnalyticsEvent(
                        name: event.event, id: event.distinctId,
                        identified: event.properties["$is_identified"] as? Bool,
                        profiles: event.properties["$process_person_profile"] as? Bool
                    ))
            }
            return nil
        }

        let previousSDK = PostHogSDK.with(config)
        if identified {
            previousSDK.identify("legacy-account")
            XCTAssertEqual(previousSDK.getDistinctId(), "legacy-account")
        }
        let previousID = previousSDK.getDistinctId()
        // Persist an SDK opt-in so setup must reconcile it with the app's preference.
        previousSDK.optOut()
        previousSDK.optIn()
        previousSDK.close()
        events.withLock { $0.removeAll() }

        let sdk = AppDelegate.initPostHog(
            config: config, defaults: defaults, optedOut: !telemetryEnabled, setup: PostHogSDK.with
        )
        defer { sdk.close() }
        let anonymousID = sdk.getDistinctId()
        XCTAssertFalse(anonymousID.isEmpty)
        XCTAssertEqual(anonymousID, sdk.getAnonymousId())
        if identified {
            XCTAssertNotEqual(anonymousID, previousID)
            XCTAssertNil(defaults.object(forKey: Analytics.legacyIdentityKey))
        } else {
            XCTAssertEqual(anonymousID, previousID, "An anonymous install must keep its anonymous ID")
        }
        XCTAssertEqual(sdk.isOptOut(), !telemetryEnabled)
        XCTAssertEqual(defaults.object(forKey: "telemetryEnabled") as? Bool, telemetryEnabled)

        sdk.capture("startup_probe")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        let captured = events.withLock { $0 }
        if telemetryEnabled {
            XCTAssertTrue(captured.contains { $0.name == "startup_probe" })
            XCTAssertTrue(
                captured.contains { $0.name == "Application Opened" }, "Migration must reinstall lifecycle listeners")
            XCTAssertTrue(
                captured.allSatisfy { $0.id == anonymousID && $0.identified == false && $0.profiles == false })
        } else {
            XCTAssertTrue(captured.isEmpty, "Opted-out startup must not collect manual or lifecycle events")
        }
        sdk.close()

        let nextSDK = AppDelegate.initPostHog(
            config: config, defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
            optedOut: !telemetryEnabled, setup: PostHogSDK.with
        )
        defer { nextSDK.close() }
        XCTAssertEqual(
            nextSDK.getDistinctId(), anonymousID, "A subsequent launch must not reset the anonymous identity")
        XCTAssertEqual(nextSDK.isOptOut(), !telemetryEnabled)
    }
}

private struct CapturedAnalyticsEvent: Sendable {
    let name: String
    let id: String
    let identified: Bool?
    let profiles: Bool?
}

// URLProtocol requires Sendable; this subclass adds no mutable state.
private final class AnalyticsNetworkBlocker: URLProtocol, @unchecked Sendable {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}
