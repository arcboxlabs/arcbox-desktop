import K8sClient
import XCTest

@testable import ArcBox

final class KubernetesWatchRetryTests: XCTestCase {
    private let shortLived = Duration.milliseconds(200)

    // MARK: - Delay

    /// The failure this guards: the LIST succeeds, the watch behind it dies at once, and
    /// every such attempt used to restart the ramp — a reconnect every two seconds, forever.
    func testShortLivedStreamsKeepRampingHoweverOftenTheyConnect() {
        var retry = WatchRetry()

        let delays = (0..<6).map { _ in retry.recordFailure(nil, streamLifetime: shortLived).delay }

        XCTAssertEqual(delays, [2, 4, 8, 15, 15, 15].map(Duration.seconds))
        XCTAssertEqual(retry.failures, 6)
    }

    func testAStreamThatNeverStartedCountsAsAFailure() {
        var retry = WatchRetry()

        _ = retry.recordFailure(nil, streamLifetime: nil)

        XCTAssertEqual(retry.recordFailure(nil, streamLifetime: nil).delay, .seconds(4))
    }

    func testAStreamThatStayedUpRestartsTheRamp() {
        var retry = WatchRetry()
        for _ in 0..<4 {
            _ = retry.recordFailure(nil, streamLifetime: nil)
        }

        let attempt = retry.recordFailure(nil, streamLifetime: WatchRetry.stableLifetime)

        XCTAssertEqual(attempt.delay, WatchRetry.minimumDelay)
        XCTAssertEqual(retry.failures, 1)
    }

    // MARK: - Reporting

    /// Each retry of a watch fails on a URL carrying a newer `resourceVersion`, so the
    /// errors differ in everything but their cause.
    func testRetriesOfOneCauseAreReportedOnce() {
        var retry = WatchRetry()
        let attempts = ["2221", "2230"].map { version in
            URLError(
                .serverCertificateUntrusted,
                userInfo: [
                    NSURLErrorFailingURLStringErrorKey: "https://127.0.0.1:16443/api/v1/pods?resourceVersion=\(version)"
                ])
        }

        let reported = attempts.map { retry.recordFailure($0, streamLifetime: shortLived).isNewCause }

        XCTAssertEqual(reported, [true, false])
    }

    /// A 503 while k3s boots must not swallow the 401 the stream then gets stuck on.
    func testADifferentCauseIsStillReported() {
        var retry = WatchRetry()
        let causes: [any Error] = [
            URLError(.serverCertificateUntrusted), URLError(.secureConnectionFailed),
            K8sError.httpError(503), K8sError.httpError(401),
        ]

        let reported = causes.map { retry.recordFailure($0, streamLifetime: shortLived).isNewCause }

        XCTAssertEqual(reported, [true, true, true, true])
    }

    /// An outage hours after a healthy stretch is news again, even with a familiar cause.
    func testACauseIsReportedAgainAfterTheStreamStayedUp() {
        var retry = WatchRetry()
        let cause = URLError(.networkConnectionLost)
        _ = retry.recordFailure(cause, streamLifetime: shortLived)

        let afterRecovery = retry.recordFailure(cause, streamLifetime: WatchRetry.stableLifetime)

        XCTAssertTrue(afterRecovery.isNewCause)
        XCTAssertFalse(retry.recordFailure(cause, streamLifetime: shortLived).isNewCause)
    }

    func testAStreamThatMerelyFinishedHasNothingToReport() {
        var retry = WatchRetry()

        XCTAssertFalse(retry.recordFailure(nil, streamLifetime: shortLived).isNewCause)
    }
}
