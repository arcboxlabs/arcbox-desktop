import Foundation
import Sparkle

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://github.com/arcboxlabs/arcbox-desktop/releases/latest/download/appcast.xml"
    }
}
