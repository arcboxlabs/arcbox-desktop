import Foundation
import OSLog
import UserNotifications

/// Delivers `AppNotification`s through the system notification centre.
///
/// The single place in the app that touches `UNUserNotificationCenter`: rules
/// decide what is worth saying, this decides whether the user needs to be told
/// at all, and routes the click back into navigation.
final class UserNotificationService: NSObject {
    /// Whether the user is already looking at what a notification is about.
    /// Supplied by the coordinator, which owns window and navigation state.
    var isUserWatching: ((DeepLink) -> Bool)?

    /// Applies a notification's destination when it is clicked.
    var openDestination: ((DeepLink) -> Void)?

    /// Authorization is requested the first time there is something to say, so
    /// the prompt arrives attached to a real event instead of at launch.
    private enum Authorization {
        case unrequested
        case granted
        case denied
    }

    private static let destinationKey = "destination"

    private let center: UNUserNotificationCenter
    private var authorization: Authorization = .unrequested

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    /// Become the delegate. Called during app launch so a click on a
    /// notification that launched the app still routes.
    func start() {
        center.delegate = self
    }

    func post(_ notification: AppNotification) {
        Task { await deliver(notification) }
    }

    // MARK: - Private

    private func deliver(_ notification: AppNotification) async {
        guard await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.userInfo = [Self.destinationKey: notification.destination.url.absoluteString]

        do {
            // A nil trigger delivers immediately.
            try await center.add(
                UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil))
        } catch {
            Log.notifications.error(
                "Failed to deliver \(notification.identifier, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func isAuthorized() async -> Bool {
        switch authorization {
        case .granted: return true
        case .denied: return false
        case .unrequested: break
        }

        // Idempotent: once the user has decided, this reports that decision
        // instead of prompting again.
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.notifications.error(
                "Notification authorization failed: \(error.localizedDescription, privacy: .private)")
            granted = false
        }
        authorization = granted ? .granted : .denied
        if !granted {
            Log.notifications.info("Notifications not authorized; no further delivery will be attempted")
        }
        return granted
    }

    private func destination(of notification: UNNotification) -> DeepLink? {
        guard let raw = notification.request.content.userInfo[Self.destinationKey] as? String,
            let url = URL(string: raw)
        else { return nil }
        return DeepLink(url)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension UserNotificationService: UNUserNotificationCenterDelegate {
    /// Only called while the app is frontmost. Suppress the banner when the
    /// user is already looking at what it would announce — that redundancy is
    /// the main reason notifications become annoying.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard let destination = destination(of: notification),
            isUserWatching?(destination) == true
        else { return [.banner, .sound] }

        Log.notifications.debug(
            "Suppressed \(notification.request.identifier, privacy: .public): already on screen")
        return []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let destination = destination(of: response.notification)
        else { return }
        openDestination?(destination)
    }
}
