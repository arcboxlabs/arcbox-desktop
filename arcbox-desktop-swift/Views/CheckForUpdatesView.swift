import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _checkForUpdatesViewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button(action: updater.checkForUpdates) {
            Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}
