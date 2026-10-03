import ArcBoxClient
import Foundation

/// Owns everything between an event and a delivered notification: which rules
/// apply, how long a verdict must hold before it is worth saying, and the
/// service that delivers it.
///
/// `ApplicationCoordinator` only forwards events here and answers the two
/// questions this cannot: whether the user is looking at something, and where
/// a click should land.
@MainActor
final class NotificationCoordinator {
    private let service: UserNotificationService
    private let isDaemonRunning: () -> Bool

    private var sandboxRules = SandboxNotificationRules()
    private var pendingDaemonAlert: Task<Void, Never>?

    init(
        service: UserNotificationService = UserNotificationService(),
        isUserWatching: @escaping (DeepLink) -> Bool,
        openDestination: @escaping (DeepLink) -> Void,
        isDaemonRunning: @escaping () -> Bool
    ) {
        self.service = service
        self.isDaemonRunning = isDaemonRunning
        service.isUserWatching = isUserWatching
        service.openDestination = openDestination
    }

    /// Become the notification delegate. Called during app launch so a click on
    /// a notification that launched the app still routes.
    func start() {
        service.start()
    }

    func stop() {
        pendingDaemonAlert?.cancel()
        pendingDaemonAlert = nil
    }

    func handleSandboxEvent(_ event: SandboxEventRecord) {
        guard let notification = sandboxRules.notification(for: event) else { return }
        service.post(notification)
    }

    /// Tell the user about a daemon problem, but only once it has outlasted the
    /// alert's confirmation window. Every state change restarts this, so a
    /// daemon that drops and recovers — waking from sleep, a stream hiccup —
    /// says nothing at all.
    func handleDaemonState(from previous: DaemonState?, to current: DaemonState) {
        pendingDaemonAlert?.cancel()
        pendingDaemonAlert = nil

        guard let alert = DaemonNotificationRules.alert(from: previous, to: current) else { return }
        guard alert.confirmAfter > .zero else {
            service.post(alert.notification)
            return
        }

        pendingDaemonAlert = Task { [weak self] in
            try? await Task.sleep(for: alert.confirmAfter)
            guard !Task.isCancelled, let self, !isDaemonRunning() else { return }
            service.post(alert.notification)
        }
    }
}
