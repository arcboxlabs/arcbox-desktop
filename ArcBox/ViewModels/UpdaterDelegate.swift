import Foundation
import Sparkle

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    @objc func feedURLString(for updater: SPUUpdater) -> String? {
        Bundle.main.infoDictionary?["SUFeedURL"] as? String
    }
}
