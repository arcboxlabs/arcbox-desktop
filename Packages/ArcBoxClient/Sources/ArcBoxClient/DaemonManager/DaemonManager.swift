import Foundation
import Observation
import ServiceManagement

/// Manages the arcbox daemon lifecycle via SMAppService (LaunchAgent) and
/// observes readiness via gRPC `WatchSetupStatus` stream.
///
/// The daemon is bundled under `Contents/Frameworks/` using the app profile's
/// launchd label (`com.arcboxlabs.desktop.daemon` or `...dev.daemon`).
/// and managed by launchd. `KeepAlive` in the plist ensures automatic restart on crash.
@Observable
@MainActor
public final class DaemonManager {
    /// Current daemon state.
    public internal(set) var state: DaemonState = .stopped

    /// Current setup phase reported by the daemon's gRPC stream.
    public internal(set) var setupPhase: DaemonSetupPhase = .unknown

    /// Human-readable status message from the daemon.
    public internal(set) var setupMessage: String = ""

    /// Whether the DNS resolver is installed (from daemon status).
    public internal(set) var dnsResolverInstalled: Bool = false

    /// Whether the Docker socket is linked (from daemon status).
    public internal(set) var dockerSocketLinked: Bool = false

    /// Whether the container subnet route is installed (from daemon status).
    public internal(set) var routeInstalled: Bool = false

    /// Whether the default VM is running (from daemon status).
    public internal(set) var vmRunning: Bool = false

    /// Whether Docker CLI tools are installed (from daemon status).
    public internal(set) var dockerToolsInstalled: Bool = false

    /// Last error message from enable/disable operations.
    public internal(set) var errorMessage: String?

    /// Number of gRPC stream reconnect attempts since the last ``connectAndWatch(client:)`` call.
    public internal(set) var reconnectCount: Int = 0

    /// Timestamp of the last message received from the gRPC setup status stream.
    public internal(set) var lastMessageTime: Date?

    nonisolated static var isDevelopmentProfile: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String)?
            .caseInsensitiveCompare("development") == .orderedSame
    }

    nonisolated static var arcboxProfile: String {
        isDevelopmentProfile ? "development" : "production"
    }

    nonisolated static var dataDirectoryName: String {
        isDevelopmentProfile ? ".arcbox-dev" : ".arcbox"
    }

    nonisolated static var daemonLabel: String {
        isDevelopmentProfile ? "com.arcboxlabs.desktop.dev.daemon" : "com.arcboxlabs.desktop.daemon"
    }

    nonisolated public static var daemonPlistName: String {
        "\(daemonLabel).plist"
    }

    nonisolated static var profileArguments: [String] {
        ["--profile", arcboxProfile]
    }

    nonisolated static var profileDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(dataDirectoryName)
    }

    nonisolated public var daemonService: SMAppService {
        SMAppService.agent(plistName: Self.daemonPlistName)
    }

    /// What to tell the user when `SMAppService` reports `.requiresApproval`, which the
    /// framework documents as "the user needs to take action in System Settings before
    /// the service is eligible to run … returned if the user revokes consent".
    public static let loginItemsApprovalMessage = """
        ArcBox is switched off in Login Items, so its background service cannot start. \
        Turn ArcBox on in System Settings > General > Login Items & Extensions, then retry.
        """

    /// Opens the pane ``loginItemsApprovalMessage`` names.
    nonisolated public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Whether the privileged helper is installed.
    public internal(set) var helperInstalled: Bool = false

    var watchTask: Task<Void, Never>?

    /// Guards `enableDaemon()` against concurrent (re-entrant) calls.
    /// Even though `@MainActor` serializes synchronous access, `await`
    /// suspension points allow a second call to interleave.  This flag
    /// is checked at entry and cleared at exit to ensure only one
    /// enable operation is in flight at a time.
    var isEnabling: Bool = false

    public init() {}
}
