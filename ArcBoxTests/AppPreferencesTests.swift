import Foundation
import XCTest

@testable import ArcBox

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testRegistersEveryDefaultWithoutOverwritingAStoredPreference() throws {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(false, forKey: "switchDockerContextAutomatically")
        AppPreferences.registerDefaults(in: userDefaults)

        XCTAssertFalse(AppPreferences.hasCompletedOnboarding(in: userDefaults))
        XCTAssertFalse(userDefaults.bool(forKey: "showInMenuBar"))
        XCTAssertEqual(userDefaults.string(forKey: "updateChannel"), "stable")
        XCTAssertEqual(userDefaults.data(forKey: "activity.containerColumns"), Data())
        XCTAssertEqual(userDefaults.string(forKey: "terminalTheme"), "system")
        XCTAssertEqual(
            userDefaults.string(forKey: "externalTerminal"),
            ExternalTerminalApp.terminalBundleIdentifier
        )
        XCTAssertFalse(userDefaults.bool(forKey: "startAtLogin"))
        XCTAssertTrue(userDefaults.bool(forKey: "telemetryEnabled"))
        XCTAssertFalse(userDefaults.bool(forKey: "includeTimeMachine"))
        XCTAssertFalse(
            userDefaults.bool(forKey: "switchDockerContextAutomatically"),
            "registered defaults must not overwrite a stored preference"
        )
        XCTAssertTrue(userDefaults.bool(forKey: "pauseContainersWhileSleeping"))
        // Notification categories are gated by `bool(forKey:)`, which reads an
        // unregistered key as false — every category must be registered or it
        // silently ships switched off.
        for category in AppNotification.Category.allCases {
            XCTAssertTrue(
                userDefaults.bool(forKey: category.preferenceKey),
                "\(category.rawValue) notifications must default to on"
            )
        }

        userDefaults.removeObject(forKey: "switchDockerContextAutomatically")
        XCTAssertTrue(userDefaults.bool(forKey: "switchDockerContextAutomatically"))

        AppPreferences.markOnboardingCompleted(in: userDefaults)
        AppPreferences.registerDefaults(in: userDefaults)
        XCTAssertTrue(
            AppPreferences.hasCompletedOnboarding(in: userDefaults),
            "registered defaults must not reset completed onboarding"
        )
    }

    func testOnboardingMigrationDistinguishesExistingAndInterruptedFirstLaunches() throws {
        let existingSuiteName = "AppPreferencesTests.existing.\(UUID().uuidString)"
        let existingDefaults = try XCTUnwrap(UserDefaults(suiteName: existingSuiteName))
        defer { existingDefaults.removePersistentDomain(forName: existingSuiteName) }
        existingDefaults.set(true, forKey: "SUHasLaunchedBefore")

        AppPreferences.registerDefaults(in: existingDefaults)

        XCTAssertTrue(AppPreferences.hasCompletedOnboarding(in: existingDefaults))

        let newSuiteName = "AppPreferencesTests.new.\(UUID().uuidString)"
        let newDefaults = try XCTUnwrap(UserDefaults(suiteName: newSuiteName))
        defer { newDefaults.removePersistentDomain(forName: newSuiteName) }

        AppPreferences.registerDefaults(in: newDefaults)
        newDefaults.set(true, forKey: "SUHasLaunchedBefore")
        AppPreferences.registerDefaults(in: newDefaults)

        XCTAssertFalse(
            AppPreferences.hasCompletedOnboarding(in: newDefaults),
            "quitting a first launch must not migrate past onboarding"
        )
    }

    func testLaunchOverrideDoesNotCompleteOnboardingOnTheNextLaunch() throws {
        let suiteName = "AppPreferencesTests.override.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let argumentDomain = UserDefaults.argumentDomain
        let originalArguments = userDefaults.volatileDomain(forName: argumentDomain)
        defer {
            userDefaults.setVolatileDomain(originalArguments, forName: argumentDomain)
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        userDefaults.setVolatileDomain(
            originalArguments.merging(["hasCompletedOnboarding": true]) { _, new in new },
            forName: argumentDomain
        )
        AppPreferences.registerDefaults(in: userDefaults)
        XCTAssertTrue(AppPreferences.hasCompletedOnboarding(in: userDefaults))

        userDefaults.set(true, forKey: "SUHasLaunchedBefore")
        userDefaults.setVolatileDomain(originalArguments, forName: argumentDomain)
        AppPreferences.registerDefaults(in: userDefaults)

        XCTAssertFalse(
            AppPreferences.hasCompletedOnboarding(in: userDefaults),
            "a one-off launch override must not become the stored preference"
        )
    }
}
