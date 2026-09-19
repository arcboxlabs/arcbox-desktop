import XCTest

@testable import ArcBox
@testable import DockerClient

/// Tests for which container deaths are worth interrupting the user for.
///
/// The event shapes here were captured from a live Docker 29.6 daemon rather
/// than assumed: `docker stop` really does produce `kill`, `kill`, `stop`,
/// `die` in that order, and its `die` carries the same `exitCode=137` a killed
/// container does — which is why intent, not the exit code, is what separates
/// them.
@MainActor
final class ContainerNotificationRulesTests: XCTestCase {

    private var rules = ContainerNotificationRules()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        rules = ContainerNotificationRules()
    }

    // MARK: - Helpers

    private func event(
        _ action: String,
        id: String = "container-abcdef123456",
        after seconds: TimeInterval = 0,
        type: String = "container",
        _ attributes: [String: String] = [:]
    ) -> DockerClient.DockerEvent {
        DockerClient.DockerEvent(
            type: type,
            action: action,
            actorID: id,
            attributes: attributes,
            date: start.addingTimeInterval(seconds)
        )
    }

    // MARK: - Crashes

    func testNonZeroExitNotifies() {
        let crash = rules.crash(for: event("die", ["exitCode": "137", "name": "api"]))

        XCTAssertEqual(crash, ContainerCrash(containerID: "container-abcdef123456", name: "api", exitCode: 137))
    }

    func testCleanExitIsSilent() {
        XCTAssertNil(rules.crash(for: event("die", ["exitCode": "0", "name": "migrate"])))
    }

    func testMissingExitCodeIsSilent() {
        XCTAssertNil(rules.crash(for: event("die", ["name": "api"])))
    }

    func testUnnamedContainerFallsBackToShortID() {
        let crash = rules.crash(for: event("die", id: "0123456789abcdef", ["exitCode": "1"]))

        XCTAssertEqual(crash?.name, "0123456789ab")
    }

    // MARK: - Intent

    /// `docker stop` produces the same non-zero `die` a crash does; what marks
    /// it is the `stop` that precedes it.
    func testStopSuppressesTheFollowingDie() {
        XCTAssertNil(rules.crash(for: event("stop")))

        XCTAssertNil(rules.crash(for: event("die", after: 1, ["exitCode": "137", "name": "api"])))
    }

    func testKillSuppressesTheFollowingDie() {
        _ = rules.crash(for: event("kill", ["signal": "15"]))

        XCTAssertNil(rules.crash(for: event("die", after: 1, ["exitCode": "137"])))
    }

    /// Intent explains exactly one death. A container stopped, restarted, then
    /// crashing on its own is news.
    func testIntentIsConsumedByOneDeath() {
        _ = rules.crash(for: event("stop"))
        _ = rules.crash(for: event("die", after: 1, ["exitCode": "137"]))
        _ = rules.crash(for: event("start", after: 2))

        XCTAssertNotNil(rules.crash(for: event("die", after: 400, ["exitCode": "1", "name": "api"])))
    }

    /// A restart clears intent even when no `die` consumed it.
    func testStartClearsPendingIntent() {
        _ = rules.crash(for: event("kill"))
        _ = rules.crash(for: event("start", after: 1))

        XCTAssertNotNil(rules.crash(for: event("die", after: 2, ["exitCode": "1"])))
    }

    /// `docker kill` sends any signal the caller asks for. SIGHUP addresses a
    /// container that is expected to keep running, so a death that follows it
    /// is the container's own doing.
    func testNonTerminatingSignalIsNotIntent() {
        _ = rules.crash(for: event("kill", ["signal": "1"]))

        XCTAssertNotNil(rules.crash(for: event("die", after: 3, ["exitCode": "1", "name": "api"])))
    }

    /// The other half: a container that traps SIGTERM and carries on must not
    /// leave intent sitting there to swallow an unrelated crash later.
    func testTrappedTerminationSignalStopsExplainingDeathsAfterTheWindow() {
        _ = rules.crash(for: event("kill", ["signal": "15"]))

        let later = ContainerNotificationRules.intentWindow + 1
        XCTAssertNotNil(rules.crash(for: event("die", after: later, ["exitCode": "1", "name": "api"])))
    }

    /// An image can name its own `STOPSIGNAL` — httpd's is SIGWINCH — so the
    /// `kill` that `docker stop` sends is not always a termination signal. The
    /// `stop` it emits before the `die` is what covers it.
    func testCustomStopSignalIsStillSuppressed() {
        _ = rules.crash(for: event("kill", ["signal": "28"]))
        _ = rules.crash(for: event("stop", after: 1))

        XCTAssertNil(rules.crash(for: event("die", after: 1, ["exitCode": "137"])))
    }

    /// A long `docker stop -t 60` is still covered: Docker emits `stop`
    /// immediately before the `die`, refreshing the intent no matter how long
    /// the grace period ran.
    func testLongGracePeriodStopIsStillSuppressed() {
        _ = rules.crash(for: event("kill", ["signal": "15"]))
        _ = rules.crash(for: event("stop", after: 60))

        XCTAssertNil(rules.crash(for: event("die", after: 60, ["exitCode": "137"])))
    }

    func testIntentIsTrackedPerContainer() {
        _ = rules.crash(for: event("stop", id: "stopped"))

        XCTAssertNil(rules.crash(for: event("die", id: "stopped", ["exitCode": "137"])))
        XCTAssertNotNil(rules.crash(for: event("die", id: "crashed", ["exitCode": "137"])))
    }

    // MARK: - Noise

    /// The trap: a failing health check emits `exec_die` with a non-zero exit
    /// code every few seconds, on a `type=container` event, and says nothing
    /// about the container itself.
    func testFailingHealthCheckProbesAreSilent() {
        for second in 0..<5 {
            XCTAssertNil(
                rules.crash(for: event("exec_die", after: TimeInterval(second), ["exitCode": "1"])),
                "exec_die must never notify"
            )
        }
    }

    /// A container under `restart: always` with a broken image dies forever.
    func testRepeatedCrashesAreRateLimited() {
        XCTAssertNotNil(rules.crash(for: event("die", ["exitCode": "1"])))

        _ = rules.crash(for: event("start", after: 2))
        XCTAssertNil(rules.crash(for: event("die", after: 5, ["exitCode": "1"])))
        _ = rules.crash(for: event("start", after: 7))
        XCTAssertNil(rules.crash(for: event("die", after: 10, ["exitCode": "1"])))
    }

    func testCrashIsReportedAgainAfterTheCooldown() {
        _ = rules.crash(for: event("die", ["exitCode": "1"]))

        let later = ContainerNotificationRules.repeatCooldown + 1
        XCTAssertNotNil(rules.crash(for: event("die", after: later, ["exitCode": "1"])))
    }

    /// A recreated container is a different container, so its cooldown is not
    /// inherited from the one it replaced.
    func testDestroyForgetsTheCooldown() {
        _ = rules.crash(for: event("die", ["exitCode": "1"]))
        _ = rules.crash(for: event("destroy", after: 1))

        XCTAssertNotNil(rules.crash(for: event("die", after: 2, ["exitCode": "1"])))
    }

    func testNonContainerEventsAreIgnored() {
        XCTAssertNil(rules.crash(for: event("die", type: "image", ["exitCode": "1"])))
    }
}
