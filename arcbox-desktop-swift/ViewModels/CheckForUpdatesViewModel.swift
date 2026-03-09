import Sparkle
import Combine

@Observable
final class CheckForUpdatesViewModel {
    var canCheckForUpdates = false

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }
}
