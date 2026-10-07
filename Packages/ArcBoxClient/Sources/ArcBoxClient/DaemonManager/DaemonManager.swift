import Foundation
import Observation
import ServiceManagement

/// Manages the arcbox daemon lifecycle via SMAppService (LaunchAgent) and
/// observes readiness via gRPC `WatchSetupStatus` stream.
///
/// The daemon is bundled under `Contents/Frameworks/` using the app profile's
/// launchd label (`com.arcboxlabs.desktop.daemon` or `...dev.daemon`).
/// and managed by launchd. `KeepAlive` in the plist ensures automatic restart on crash.
///
/// Quitting the app unregisters the daemon. launchd then sends SIGTERM and, after the
/// plist's `ExitTimeOut`, SIGKILL; the daemon spends that window draining its API servers
/// and stopping the VM, so ``disableDaemon()`` waits for the process to exit and the quit
/// finishes only once the VM is down.
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

    /// Last storage observation, retained for diagnostics after a disconnect.
    public internal(set) var storageHealth: RuntimeStorageHealth?

    /// Latest server-owned recovery operation, including its terminal outcome.
    public internal(set) var storageRecovery: Arcbox_V1_StorageRecoveryProgress?

    /// False after the VM stops or the setup stream disconnects.
    public internal(set) var storageHealthIsCurrent = false

    /// Storage failures do not change Docker API readiness or remove readable resources.
    public var storageWriteFailureMessage: String? {
        if let recovery = storageRecovery, recovery.phase != .complete, recovery.phase != .failed {
            return
                "Runtime storage recovery is in progress. Wait for recovery to finish before starting a write operation."
        }
        if storageRecovery?.storageProtected == true {
            return "Runtime storage remains protected. Use Recover Read-Write in Storage & Recovery "
                + "before starting a write operation."
        }
        guard storageHealthIsCurrent, setupPhase.isDockerReady else { return nil }
        return storageHealth?.writeFailureMessage
    }

    /// Last error message from enable/disable operations.
    public internal(set) var errorMessage: String?

    /// Number of gRPC stream reconnect attempts since the last ``connectAndWatch(client:)`` call.
    public internal(set) var reconnectCount: Int = 0

    /// Timestamp of the last message received from the gRPC setup status stream.
    public internal(set) var lastMessageTime: Date?

    /// Whether this bundle runs the development profile (`~/.arcbox-dev`, the `arcbox-dev`
    /// Docker context, and its own daemon label).
    nonisolated public static var isDevelopmentProfile: Bool {
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

    /// The lock a running daemon holds for its lifetime; see ``DaemonLock``.
    nonisolated static var daemonLockFile: URL {
        profileDataDirectory.appendingPathComponent("run/daemon.lock")
    }

    /// How long ``disableDaemon()`` waits for the daemon to exit. launchd SIGKILLs it at
    /// the plist's `ExitTimeOut` (45 s), so this only needs a little slack past that.
    static let shutdownTimeout: Duration = .seconds(50)

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
