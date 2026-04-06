import Combine
import Sparkle

@MainActor
@Observable
final class CheckForUpdatesViewModel {
    var canCheckForUpdates = false

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] newValue in
                Task { @MainActor in
                    self?.canCheckForUpdates = newValue
                }
            }
    }
}
