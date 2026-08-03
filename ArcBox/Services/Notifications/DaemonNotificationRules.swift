import ArcBoxClient
import Foundation

/// Decides when a daemon state change is worth interrupting the user for.
///
/// The app keeps running with its window closed, so a daemon that dies is
/// otherwise invisible until the window is reopened.
enum DaemonNotificationRules {
    /// Both cases reuse one identifier: the daemon has a single health story,
    /// and a later verdict should replace the earlier one rather than leave two
    /// banners disagreeing.
    private static let identifier = "daemon.health"

    /// `DaemonManager` holds `.running` through transient stream drops (daemon
    /// GC pause, HTTP/2 GOAWAY) for a ~3 s grace window before regressing to
    /// `.registered`, so reaching either state here already means the daemon is
    /// genuinely gone. No further debounce belongs at this layer.
    ///
    /// `.stopping` and `.stopped` are deliberately not covered: those are the
    /// states of a shutdown the user asked for.
    static func notification(from previous: DaemonState?, to current: DaemonState) -> AppNotification? {
        guard previous != current else { return nil }

        switch (previous, current) {
        case (_, .error(let reason)):
            return AppNotification(
                identifier: identifier,
                title: "ArcBox daemon stopped",
                body: reason.isEmpty ? "The daemon reported a fatal error." : reason,
                destination: .main
            )

        case (.some(.running), .registered):
            return AppNotification(
                identifier: identifier,
                title: "ArcBox daemon is unreachable",
                body: "Containers and sandboxes are no longer running.",
                destination: .main
            )

        default:
            return nil
        }
    }
}
