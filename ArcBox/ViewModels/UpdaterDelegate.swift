import Foundation
import Sparkle

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    @objc func feedURLString(for updater: SPUUpdater) -> String? {
        guard let baseURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
              let url = URL(string: baseURL) else {
            return nil
        }
        let channel = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        // CI sets SUFeedURL to ".../desktop/appcast/{channel}.xml" (e.g. stable.xml).
        // Swap the last path component to match the selected channel.
        let currentFilename = url.lastPathComponent
        let targetFilename: String
        switch channel {
        case "beta":
            if currentFilename == "stable.xml" {
                targetFilename = "beta.xml"
            } else if currentFilename == "appcast.xml" {
                targetFilename = "appcast-beta.xml"
            } else {
                return baseURL
            }
        default:
            if currentFilename == "beta.xml" {
                targetFilename = "stable.xml"
            } else if currentFilename == "appcast-beta.xml" {
                targetFilename = "appcast.xml"
            } else {
                return baseURL
            }
        }
        return url.deletingLastPathComponent().appendingPathComponent(targetFilename).absoluteString
    }
}
