import Foundation
import XCTest

@testable import ArcBox

final class AnalyticsIdentityMigrationTests: XCTestCase {
    func testAccountIdentityResetsOnceAcrossLaunchesWithoutChangingTelemetryPreference() throws {
        let suiteName = "AnalyticsIdentityMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "telemetryEnabled")
        var resetCount = 0

        XCTAssertFalse(Analytics.resetLegacyIdentityIfNeeded(defaults: defaults) { resetCount += 1 })
        XCTAssertEqual(resetCount, 0, "An anonymous install must keep its anonymous ID")

        defaults.set(true, forKey: "analyticsIdentified")
        XCTAssertTrue(
            Analytics.resetLegacyIdentityIfNeeded(defaults: defaults) {
                XCTAssertTrue(defaults.bool(forKey: "analyticsIdentified"))
                resetCount += 1
            }
        )
        XCTAssertEqual(resetCount, 1)
        XCTAssertNil(defaults.object(forKey: "analyticsIdentified"))
        XCTAssertEqual(defaults.object(forKey: "telemetryEnabled") as? Bool, false)

        let nextLaunch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertFalse(Analytics.resetLegacyIdentityIfNeeded(defaults: nextLaunch) { resetCount += 1 })
        XCTAssertEqual(resetCount, 1, "A completed migration must not reset the next launch")
    }
}
