import ArcBoxClient
import Foundation

/// A daemon health notification, and how long the daemon has to stay in the
/// state that produced it before the user is told.
struct DaemonHealthAlert: Equatable {
    let notification: AppNotification
    /// `.zero` when the daemon has already reached a verdict of its own and
    /// waiting would add nothing.
    let confirmAfter: Duration
}

/// Decides when a daemon state change is worth interrupting the user for.
///
/// The app keeps running with its window closed, so a daemon that dies is
/// otherwise invisible until the window is reopened.
enum DaemonNotificationRules {
    /// How long the daemon must stay unreachable before it is worth saying.
    ///
    /// `DaemonManager` drops to `.registered` after ~3.5 s of failed
    /// reconnects, which is tuned for the UI — long enough to ride out a
    /// GOAWAY, short enough that the window does not lie. That is far too
    /// eager for a notification: waking from sleep reliably breaks the stream
    /// while the daemon is still resuming the VM, and a banner on every wake
    /// is exactly what makes people switch notifications off. Confirming over
    /// a longer window separates "briefly disconnected" from "gone" without
    /// making the window sluggish.
    static let unreachableConfirmation: Duration = .seconds(30)

    /// Both cases reuse one identifier: the daemon has a single health story,
    /// and a later verdict should replace the earlier one rather than leave two
    /// banners disagreeing.
    private static let identifier = "daemon.health"

    /// `.stopping` and `.stopped` are deliberately not covered: those are the
    /// states of a shutdown the user asked for.
    static func alert(from previous: DaemonState?, to current: DaemonState) -> DaemonHealthAlert? {
        guard previous != current else { return nil }

        switch (previous, current) {
        case (_, .error(let reason)):
            // The daemon reported a fatal setup failure and gave up. It is not
            // coming back on its own, so there is nothing to confirm.
            return DaemonHealthAlert(
                notification: AppNotification(
                    identifier: identifier,
                    title: "ArcBox daemon stopped",
                    body: reason.isEmpty ? "The daemon reported a fatal error." : reason,
                    destination: .main,
                    category: .daemonHealth
                ),
                confirmAfter: .zero
            )

        case (.some(.running), .registered):
            return DaemonHealthAlert(
                notification: AppNotification(
                    identifier: identifier,
                    title: "ArcBox daemon is unreachable",
                    body: "Containers and sandboxes are no longer running.",
                    destination: .main,
                    category: .daemonHealth
                ),
                confirmAfter: unreachableConfirmation
            )

        default:
            return nil
        }
    }
}
