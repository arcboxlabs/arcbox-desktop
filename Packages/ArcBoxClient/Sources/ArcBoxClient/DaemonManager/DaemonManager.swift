import Foundation
import Observation
import ServiceManagement

/// Manages the arcbox daemon lifecycle via SMAppService (LaunchAgent) and
/// observes readiness via gRPC `WatchSetupStatus` stream.
///
/// The daemon is bundled as `Contents/Frameworks/com.arcboxlabs.desktop.daemon.app`
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

    nonisolated static let daemonPlistName = "com.arcboxlabs.desktop.daemon.plist"
    nonisolated var daemonService: SMAppService {
        SMAppService.agent(plistName: Self.daemonPlistName)
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
