import AppKit
import Foundation

enum ExternalTerminalDiscovery {
    private static let legacyPreferenceBundleIDs = [
        "terminal": ExternalTerminalApp.terminalBundleIdentifier,
        "iterm": "com.googlecode.iterm2",
    ]

    private static let appleScriptBackends: [String: ExternalTerminalApp.AppleScriptBackend] = [
        ExternalTerminalApp.terminalBundleIdentifier: .terminal,
        "com.googlecode.iterm2": .iTerm,
    ]

    private static let likelyTerminalNameTokens = [
        "terminal",
        "iterm",
        "term",
        "warp",
        "ghostty",
        "wezterm",
        "alacritty",
        "kitty",
        "tabby",
        "hyper",
        "rio",
    ]

    static func availableTerminals(preferredBundleIdentifier: String? = nil) -> [ExternalTerminalApp] {
        var terminals: [ExternalTerminalApp] = []
        var seenBundleIDs = Set<String>()
        let commandHandlerAppURLs = commandFileHandlerAppURLs()
        let commandHandlerBundleIDs = Set(
            commandHandlerAppURLs.compactMap { Bundle(url: $0)?.bundleIdentifier }
        )

        if let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: ExternalTerminalApp.terminalBundleIdentifier
        ) {
            terminals.append(
                ExternalTerminalApp(
                    id: ExternalTerminalApp.terminalBundleIdentifier,
                    displayName: displayName(for: terminalURL) ?? "Terminal",
                    bundleIdentifier: ExternalTerminalApp.terminalBundleIdentifier,
                    appURL: terminalURL,
                    supportsCommandFiles: commandHandlerBundleIDs.contains(
                        ExternalTerminalApp.terminalBundleIdentifier
                    ),
                    appleScriptBackend: .terminal
                )
            )
            seenBundleIDs.insert(ExternalTerminalApp.terminalBundleIdentifier)
        }

        for appURL in commandHandlerAppURLs {
            guard let bundle = Bundle(url: appURL),
                let bundleID = bundle.bundleIdentifier,
                seenBundleIDs.insert(bundleID).inserted,
                isLikelyTerminal(appURL: appURL, bundleID: bundleID)
            else { continue }

            terminals.append(terminalApp(for: appURL, bundleID: bundleID, supportsCommandFiles: true))
        }

        if let preferredBundleIdentifier,
            !seenBundleIDs.contains(preferredBundleIdentifier),
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredBundleIdentifier)
        {
            terminals.append(
                terminalApp(
                    for: appURL,
                    bundleID: preferredBundleIdentifier,
                    supportsCommandFiles: commandHandlerBundleIDs.contains(preferredBundleIdentifier)
                )
            )
        }

        terminals.sort { lhs, rhs in
            let lhsPriority = sortPriority(for: lhs)
            let rhsPriority = sortPriority(for: rhs)
            guard lhsPriority == rhsPriority else { return lhsPriority < rhsPriority }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }

        return terminals
    }

    static func terminalApp(for appURL: URL, commandHandlerBundleIDs: Set<String>) -> ExternalTerminalApp? {
        guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        return terminalApp(
            for: appURL,
            bundleID: bundleID,
            supportsCommandFiles: commandHandlerBundleIDs.contains(bundleID)
        )
    }

    static func resolve(preference: String) -> ExternalTerminalApp {
        let terminals = availableTerminals()
        let normalized = normalizedPreference(preference, availableTerminals: terminals)
        return terminals.first { $0.id == normalized } ?? terminals.first ?? terminalFallback()
    }

    static func normalizedPreference(
        _ preference: String,
        availableTerminals terminals: [ExternalTerminalApp]? = nil
    ) -> String {
        let availableTerminals = terminals ?? availableTerminals()
        let availableIDs = Set(availableTerminals.map(\.id))
        let normalized: String

        switch preference {
        case ExternalTerminalApp.legacySystemDefaultID, "lastUsed":
            normalized = ExternalTerminalApp.terminalBundleIdentifier
        case let preference where legacyPreferenceBundleIDs[preference] != nil:
            normalized = legacyPreferenceBundleIDs[preference] ?? ExternalTerminalApp.terminalBundleIdentifier
        default:
            normalized = preference
        }

        if availableIDs.contains(normalized) {
            return normalized
        }
        return availableIDs.contains(ExternalTerminalApp.terminalBundleIdentifier)
            ? ExternalTerminalApp.terminalBundleIdentifier
            : availableTerminals.first?.id ?? ExternalTerminalApp.terminalBundleIdentifier
    }

    private static func commandFileHandlerAppURLs() -> [URL] {
        let probeURL = FileManager.default.temporaryDirectory
            .appending(path: "arcbox-terminal-handler-probe-\(UUID().uuidString).command")

        do {
            try "#!/bin/zsh\n".write(to: probeURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: probeURL) }
            return NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
        } catch {
            return []
        }
    }

    private static func isLikelyTerminal(appURL: URL, bundleID: String) -> Bool {
        let bundleID = bundleID.lowercased()
        let appName = appURL.deletingPathExtension().lastPathComponent.lowercased()
        return likelyTerminalNameTokens.contains { token in
            bundleID.contains(token) || appName.contains(token)
        }
    }

    private static func sortPriority(for terminal: ExternalTerminalApp) -> Int {
        terminal.bundleIdentifier == ExternalTerminalApp.terminalBundleIdentifier ? 0 : 1
    }

    private static func terminalApp(
        for appURL: URL,
        bundleID: String,
        supportsCommandFiles: Bool
    ) -> ExternalTerminalApp {
        ExternalTerminalApp(
            id: bundleID,
            displayName: displayName(for: appURL) ?? appURL.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleID,
            appURL: appURL,
            supportsCommandFiles: supportsCommandFiles,
            appleScriptBackend: appleScriptBackends[bundleID]
        )
    }

    private static func terminalFallback() -> ExternalTerminalApp {
        ExternalTerminalApp(
            id: ExternalTerminalApp.terminalBundleIdentifier,
            displayName: "Terminal",
            bundleIdentifier: ExternalTerminalApp.terminalBundleIdentifier,
            appURL: NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: ExternalTerminalApp.terminalBundleIdentifier
            ),
            supportsCommandFiles: true,
            appleScriptBackend: .terminal
        )
    }

    private static func displayName(for appURL: URL) -> String? {
        guard let bundle = Bundle(url: appURL) else { return nil }
        let dictionaries = [bundle.localizedInfoDictionary, bundle.infoDictionary]
        for dictionary in dictionaries {
            if let displayName = dictionary?["CFBundleDisplayName"] as? String, !displayName.isEmpty {
                return displayName
            }
            if let bundleName = dictionary?["CFBundleName"] as? String, !bundleName.isEmpty {
                return bundleName
            }
        }
        return nil
    }
}
