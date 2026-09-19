import Foundation

enum AppPreferences {
    private static let onboardingCompletedKey = "hasCompletedOnboarding"
    private static let onboardingInitializedKey = "hasInitializedOnboardingPreference"
    // Sparkle has persisted this key since before onboarding existed, so it
    // distinguishes an upgrade from a genuinely new installation.
    private static let sparkleHasLaunchedBeforeKey = "SUHasLaunchedBefore"

    static func registerDefaults(in userDefaults: UserDefaults = .standard) {
        let hasLaunchOverride =
            userDefaults.volatileDomain(forName: UserDefaults.argumentDomain)[
                onboardingCompletedKey
            ] != nil
        if !userDefaults.bool(forKey: onboardingInitializedKey) {
            let hasLaunchedBefore = userDefaults.bool(forKey: sparkleHasLaunchedBeforeKey)
            // Argument-domain values are intentionally temporary; initialize
            // the stored value from the pre-existing Sparkle marker instead.
            let hasCompletedOnboarding =
                hasLaunchOverride
                ? hasLaunchedBefore
                : userDefaults.bool(forKey: onboardingCompletedKey) || hasLaunchedBefore
            userDefaults.set(hasCompletedOnboarding, forKey: onboardingCompletedKey)
            userDefaults.set(true, forKey: onboardingInitializedKey)
        }

        userDefaults.register(defaults: [
            onboardingCompletedKey: false,
            onboardingInitializedKey: false,
            "showInMenuBar": false,
            "updateChannel": "stable",
            "activity.containerColumns": Data(),
            "terminalTheme": "system",
            "externalTerminal": ExternalTerminalApp.terminalBundleIdentifier,
            "startAtLogin": false,
            "telemetryEnabled": true,
            "includeTimeMachine": false,
            "switchDockerContextAutomatically": true,
            "pauseContainersWhileSleeping": true,
        ])

        // Delivery is gated by `bool(forKey:)`, which reads an unregistered key
        // as false. Registering from `allCases` is what stops a new category
        // from silently shipping switched off.
        userDefaults.register(
            defaults: Dictionary(
                uniqueKeysWithValues: AppNotification.Category.allCases.map { ($0.preferenceKey, true) }
            ))
    }

    static func hasCompletedOnboarding(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: onboardingCompletedKey)
    }

    static func markOnboardingCompleted(in userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: onboardingCompletedKey)
    }
}
