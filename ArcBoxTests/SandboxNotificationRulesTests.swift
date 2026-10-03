import XCTest

@testable import ArcBox

/// Tests for which sandbox events produce a user notification.
///
/// The rules are a pure value type, so every case is driven by feeding events
/// directly — no gRPC stream and no notification centre involved.
@MainActor
final class SandboxNotificationRulesTests: XCTestCase {

    private var rules = SandboxNotificationRules()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        rules = SandboxNotificationRules()
    }

    // MARK: - Helpers

    private func event(
        _ kind: SandboxEventKind,
        id: String = "sandbox-abcdef123456",
        after seconds: TimeInterval = 0,
        _ attributes: [String: String] = [:]
    ) -> SandboxEventRecord {
        SandboxEventRecord(
            sandboxID: id,
            kind: kind,
            timestamp: start.addingTimeInterval(seconds),
            attributes: attributes
        )
    }

    // MARK: - Successful completions

    func testLongSuccessNotifies() {
        XCTAssertNil(rules.notification(for: event(.running)))

        let notification = rules.notification(for: event(.idle, after: 60, ["exit_code": "0"]))

        XCTAssertEqual(notification?.title, "Sandbox execution finished")
    }

    /// Clicking a result lands on the sandbox it is about, not just the list.
    func testNotificationsPointAtTheSandbox() {
        let notification = rules.notification(for: event(.failed, id: "sandbox-xyz"))

        XCTAssertEqual(notification?.destination, .section(.sandboxes, id: "sandbox-xyz"))
    }

    /// A quick success finished while the user was still looking at it.
    func testShortSuccessIsSilent() {
        _ = rules.notification(for: event(.running))

        XCTAssertNil(rules.notification(for: event(.idle, after: 5, ["exit_code": "0"])))
    }

    /// The app launched partway through the execution, so there is no duration
    /// to judge. Guessing "long enough" here would notify on every reconnect.
    func testSuccessWithoutObservedStartIsSilent() {
        XCTAssertNil(rules.notification(for: event(.idle, after: 900, ["exit_code": "0"])))
    }

    /// The start is consumed by the completion it explains; a second completion
    /// must not reuse it.
    func testStartIsNotReusedByASecondCompletion() {
        _ = rules.notification(for: event(.running))
        XCTAssertNotNil(rules.notification(for: event(.idle, after: 60, ["exit_code": "0"])))

        XCTAssertNil(rules.notification(for: event(.idle, after: 120, ["exit_code": "0"])))
    }

    func testDurationIsTrackedPerSandbox() {
        _ = rules.notification(for: event(.running, id: "long"))
        _ = rules.notification(for: event(.running, id: "short", after: 55))

        XCTAssertNotNil(rules.notification(for: event(.idle, id: "long", after: 60, ["exit_code": "0"])))
        XCTAssertNil(rules.notification(for: event(.idle, id: "short", after: 60, ["exit_code": "0"])))
    }

    // MARK: - Failures

    /// Failures are worth saying regardless of how long they took, and without
    /// having seen the execution start.
    func testNonZeroExitNotifiesEvenWhenShortAndUnobserved() {
        let notification = rules.notification(for: event(.idle, after: 1, ["exit_code": "137"]))

        XCTAssertEqual(notification?.title, "Sandbox execution failed")
        XCTAssertEqual(notification?.body.contains("137"), true)
    }

    func testSignalNotifies() {
        let notification = rules.notification(for: event(.idle, ["signal": "SIGKILL"]))

        XCTAssertEqual(notification?.title, "Sandbox execution killed")
        XCTAssertEqual(notification?.body.contains("SIGKILL"), true)
    }

    /// On `idle`, an "error" attribute means the session broke before an exit
    /// code was observed.
    func testBrokenSessionNotifies() {
        let notification = rules.notification(for: event(.idle, ["error": "connection reset"]))

        XCTAssertEqual(notification?.title, "Sandbox execution failed")
        XCTAssertEqual(notification?.body.contains("connection reset"), true)
    }

    func testFailedNotifiesWithReason() {
        let notification = rules.notification(for: event(.failed, ["error": "no space left on device"]))

        XCTAssertEqual(notification?.title, "Sandbox failed")
        XCTAssertEqual(notification?.body.contains("no space left on device"), true)
    }

    func testFailedWithoutReasonStillNotifies() {
        XCTAssertEqual(rules.notification(for: event(.failed))?.title, "Sandbox failed")
    }

    /// An empty attribute is not a reason.
    func testEmptyErrorAttributeFallsBackToGenericBody() {
        let notification = rules.notification(for: event(.failed, ["error": ""]))

        XCTAssertEqual(notification?.body.contains("unrecoverable"), true)
    }

    // MARK: - Silent lifecycle

    func testLifecycleEventsAreSilent() {
        let silent: [SandboxEventKind] = [
            .created, .ready, .stopping, .stopped, .removed, .pausing, .paused, .resumed, .unknown,
        ]
        for kind in silent {
            XCTAssertNil(rules.notification(for: event(kind)), "\(kind.label) should be silent")
        }
    }

    /// A pause suspends the execution rather than ending it, so the completion
    /// that follows a resume is still judged against the original start.
    func testPauseDoesNotDiscardTheExecutionStart() {
        _ = rules.notification(for: event(.running))
        _ = rules.notification(for: event(.paused, after: 10))
        _ = rules.notification(for: event(.resumed, after: 20))

        XCTAssertNotNil(rules.notification(for: event(.idle, after: 60, ["exit_code": "0"])))
    }

    // MARK: - Delivery identity

    /// Two executions finishing are two results; the second must not replace
    /// the first's banner.
    func testCompletionsOfOneSandboxGetDistinctIdentifiers() {
        _ = rules.notification(for: event(.running))
        let first = rules.notification(for: event(.idle, after: 60, ["exit_code": "0"]))
        _ = rules.notification(for: event(.running, after: 120))
        let second = rules.notification(for: event(.idle, after: 180, ["exit_code": "0"]))

        XCTAssertNotNil(first?.identifier)
        XCTAssertNotEqual(first?.identifier, second?.identifier)
    }

    /// Failures are the opposite: an execution retrying in a loop should leave
    /// its latest result on screen, not one banner per attempt.
    func testFailuresOfOneSandboxShareAnIdentifier() {
        let first = rules.notification(for: event(.idle, after: 1, ["exit_code": "1"]))
        let second = rules.notification(for: event(.idle, after: 2, ["exit_code": "1"]))

        XCTAssertNotNil(first?.identifier)
        XCTAssertEqual(first?.identifier, second?.identifier)
    }

    func testFailuresOfDifferentSandboxesDoNotReplaceEachOther() {
        let a = rules.notification(for: event(.idle, id: "sandbox-a", ["exit_code": "1"]))
        let b = rules.notification(for: event(.idle, id: "sandbox-b", ["exit_code": "1"]))

        XCTAssertNotEqual(a?.identifier, b?.identifier)
    }

    func testSandboxNotificationsAreSwitchableOnTheirOwn() {
        XCTAssertEqual(rules.notification(for: event(.failed))?.category, .sandbox)
    }
}
