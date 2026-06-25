import Foundation

extension AboutView {
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var daemonVersion: String {
        guard let url = Bundle.main.url(forResource: "arcbox", withExtension: "version"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "Unknown"
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var architecture: String {
        #if arch(arm64)
            return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
            return "Intel (x86_64)"
        #else
            return "Unknown"
        #endif
    }
}
