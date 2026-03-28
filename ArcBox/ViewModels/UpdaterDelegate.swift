import Foundation
import Sparkle

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    @objc func feedURLString(for updater: SPUUpdater) -> String? {
        guard let baseURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String else {
            return nil
        }
        let channel = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        if channel == "beta" {
            // Replace the appcast filename to point to the beta feed.
            // e.g. ".../appcast.xml" → ".../appcast-beta.xml"
            return baseURL.replacingOccurrences(of: "appcast.xml", with: "appcast-beta.xml")
        }
        return baseURL
    }
}
