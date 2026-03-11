import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    @State private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _checkForUpdatesViewModel = State(initialValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button(action: updater.checkForUpdates) {
            Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}
