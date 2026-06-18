import Foundation

struct ExternalTerminalApp: Identifiable, Hashable, Sendable {
    enum AppleScriptBackend: Hashable, Sendable {
        case terminal
        case iTerm
    }

    static let legacySystemDefaultID = "system"
    static let terminalBundleIdentifier = "com.apple.Terminal"

    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let appURL: URL?
    let supportsCommandFiles: Bool
    let appleScriptBackend: AppleScriptBackend?
}
