import Foundation

/// A notification the app has decided to deliver, expressed independently of
/// `UserNotifications`.
///
/// Rules produce these as plain values and `UserNotificationService` owns
/// everything that touches the system notification centre. Keeping the decision
/// separate from the delivery is what makes the trigger conditions testable.
struct AppNotification: Equatable {
    /// Delivery identity. Posting the same identifier again replaces the
    /// earlier notification instead of stacking a duplicate.
    let identifier: String
    let title: String
    let body: String
    /// Where clicking the notification takes the user.
    let destination: DeepLink
}
