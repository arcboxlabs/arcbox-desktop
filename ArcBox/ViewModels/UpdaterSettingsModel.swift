import Combine
import Sparkle

/// Bridges Sparkle's auto-update settings to SwiftUI.
///
/// `SPUUpdater` is the single source of truth: it persists these settings in the
/// app's user defaults, seeded by the `SUEnableAutomaticChecks` and
/// `SUAutomaticallyUpdate` Info.plist defaults. This model mirrors the relevant
/// properties observably so the settings toggles reflect changes made anywhere —
/// including Sparkle's own update dialog — without a duplicate `@AppStorage` that
/// could drift out of sync with Sparkle's persisted state.
@MainActor
@Observable
final class UpdaterSettingsModel {
    private(set) var automaticallyChecksForUpdates: Bool
    private(set) var automaticallyDownloadsUpdates: Bool
    /// Whether automatic downloading can be enabled. Sparkle gates this behind
    /// automatic checks, so it drives the download toggle's enabled state.
    private(set) var allowsAutomaticUpdates: Bool

    @ObservationIgnored
    private let updater: SPUUpdater
    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = []

    init(updater: SPUUpdater) {
        self.updater = updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates

        // Reflect changes made outside the settings UI (e.g. Sparkle's own update
        // dialog). Setting `automaticallyChecksForUpdates` also re-derives the
        // gated download/allows properties, so observing all three keeps the
        // mirrors consistent.
        let observedKeyPaths: [KeyPath<SPUUpdater, Bool>] = [
            \.automaticallyChecksForUpdates,
            \.automaticallyDownloadsUpdates,
            \.allowsAutomaticUpdates,
        ]
        for keyPath in observedKeyPaths {
            updater.publisher(for: keyPath)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
                .store(in: &cancellables)
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updater.automaticallyDownloadsUpdates = enabled
        refresh()
    }

    private func refresh() {
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
    }
}
