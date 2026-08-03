import ArcBoxClient
import XCTest

@testable import ArcBox

/// Tests for which daemon state transitions produce a user notification.
///
/// The distinction that matters: a daemon that died on its own is worth
/// interrupting the user for, a shutdown they asked for is not.
@MainActor
final class DaemonNotificationRulesTests: XCTestCase {

    private func notification(from previous: DaemonState?, to current: DaemonState) -> AppNotification? {
        DaemonNotificationRules.notification(from: previous, to: current)
    }

    // MARK: - Worth saying

    /// `DaemonManager` only regresses a running daemon to `.registered` after
    /// its reconnect grace window, so this transition means genuinely gone.
    func testRunningToRegisteredNotifies() {
        XCTAssertEqual(notification(from: .running, to: .registered)?.title, "ArcBox daemon is unreachable")
    }

    func testFatalErrorNotifiesWithReason() {
        let result = notification(from: .running, to: .error("vm failed to boot"))

        XCTAssertEqual(result?.title, "ArcBox daemon stopped")
        XCTAssertEqual(result?.body, "vm failed to boot")
    }

    func testFatalErrorFromAnyStateNotifies() {
        XCTAssertNotNil(notification(from: .starting, to: .error("boom")))
        XCTAssertNotNil(notification(from: nil, to: .error("boom")))
    }

    /// A different fatal cause is new information.
    func testChangedErrorReasonNotifiesAgain() {
        XCTAssertNotNil(notification(from: .error("first"), to: .error("second")))
    }

    func testEmptyErrorReasonFallsBackToGenericBody() {
        XCTAssertEqual(notification(from: .running, to: .error(""))?.body, "The daemon reported a fatal error.")
    }

    /// One health story: a later verdict replaces the earlier banner.
    func testHealthNotificationsShareAnIdentifier() {
        XCTAssertEqual(
            notification(from: .running, to: .registered)?.identifier,
            notification(from: .running, to: .error("boom"))?.identifier
        )
    }

    // MARK: - Not worth saying

    /// `.stopping` and `.stopped` are the states of a shutdown the user asked for.
    func testIntentionalShutdownIsSilent() {
        XCTAssertNil(notification(from: .running, to: .stopping))
        XCTAssertNil(notification(from: .running, to: .stopped))
    }

    func testStartupIsSilent() {
        XCTAssertNil(notification(from: nil, to: .stopped))
        XCTAssertNil(notification(from: nil, to: .registered))
        XCTAssertNil(notification(from: .starting, to: .registered))
        XCTAssertNil(notification(from: .registered, to: .running))
    }

    /// A daemon that was never up cannot become unreachable.
    func testRegisteredToRegisteredIsSilent() {
        XCTAssertNil(notification(from: .registered, to: .registered))
    }

    func testRepeatedErrorIsSilent() {
        XCTAssertNil(notification(from: .error("same"), to: .error("same")))
    }
}
