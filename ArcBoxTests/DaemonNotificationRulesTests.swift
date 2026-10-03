import ArcBoxClient
import XCTest

@testable import ArcBox

/// Tests for which daemon state transitions produce a user notification, and
/// how long the daemon has to stay broken before the user hears about it.
///
/// The distinctions that matter: a daemon that died on its own is worth
/// interrupting the user for, a shutdown they asked for is not, and a drop that
/// recovers on its own — waking from sleep — must not say anything at all.
@MainActor
final class DaemonNotificationRulesTests: XCTestCase {

    private func alert(from previous: DaemonState?, to current: DaemonState) -> DaemonHealthAlert? {
        DaemonNotificationRules.alert(from: previous, to: current)
    }

    // MARK: - Worth saying

    func testRunningToRegisteredNotifies() {
        XCTAssertEqual(
            alert(from: .running, to: .registered)?.notification.title, "ArcBox daemon is unreachable")
    }

    /// The regression that matters: `DaemonManager` gives up on a stream after
    /// ~3.5 s, which is tuned for the window, not for a banner. Waking from
    /// sleep breaks the stream every time, so an unreachable daemon must be
    /// confirmed over a longer window before the user is told.
    func testUnreachableIsConfirmedBeforeNotifying() {
        let confirmAfter = alert(from: .running, to: .registered)?.confirmAfter

        XCTAssertEqual(confirmAfter, DaemonNotificationRules.unreachableConfirmation)
        XCTAssertGreaterThan(confirmAfter ?? .zero, .seconds(10))
    }

    /// A fatal setup failure is the daemon's own verdict; it is not coming back
    /// on its own, so there is nothing to wait for.
    func testFatalErrorNotifiesImmediately() {
        let result = alert(from: .running, to: .error("vm failed to boot"))

        XCTAssertEqual(result?.notification.title, "ArcBox daemon stopped")
        XCTAssertEqual(result?.notification.body, "vm failed to boot")
        XCTAssertEqual(result?.confirmAfter, .zero)
    }

    func testFatalErrorFromAnyStateNotifies() {
        XCTAssertNotNil(alert(from: .starting, to: .error("boom")))
        XCTAssertNotNil(alert(from: nil, to: .error("boom")))
    }

    /// A different fatal cause is new information.
    func testChangedErrorReasonNotifiesAgain() {
        XCTAssertNotNil(alert(from: .error("first"), to: .error("second")))
    }

    func testEmptyErrorReasonFallsBackToGenericBody() {
        XCTAssertEqual(
            alert(from: .running, to: .error(""))?.notification.body,
            "The daemon reported a fatal error."
        )
    }

    /// One health story: a later verdict replaces the earlier banner.
    func testHealthNotificationsShareAnIdentifier() {
        XCTAssertEqual(
            alert(from: .running, to: .registered)?.notification.identifier,
            alert(from: .running, to: .error("boom"))?.notification.identifier
        )
    }

    func testHealthNotificationsAreSwitchableOnTheirOwn() {
        XCTAssertEqual(alert(from: .running, to: .registered)?.notification.category, .daemonHealth)
    }

    // MARK: - Not worth saying

    /// `.stopping` and `.stopped` are the states of a shutdown the user asked for.
    func testIntentionalShutdownIsSilent() {
        XCTAssertNil(alert(from: .running, to: .stopping))
        XCTAssertNil(alert(from: .running, to: .stopped))
    }

    func testStartupIsSilent() {
        XCTAssertNil(alert(from: nil, to: .stopped))
        XCTAssertNil(alert(from: nil, to: .registered))
        XCTAssertNil(alert(from: .starting, to: .registered))
        XCTAssertNil(alert(from: .registered, to: .running))
    }

    /// A daemon that was never up cannot become unreachable.
    func testRegisteredToRegisteredIsSilent() {
        XCTAssertNil(alert(from: .registered, to: .registered))
    }

    func testRepeatedErrorIsSilent() {
        XCTAssertNil(alert(from: .error("same"), to: .error("same")))
    }
}
