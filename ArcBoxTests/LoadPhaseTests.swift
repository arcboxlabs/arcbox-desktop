import GRPCCore
import XCTest

@testable import ArcBox

/// `cancelLoading(for:)` keys on the task's own cancellation, not on the
/// error's shape. grpc-swift reports a cancelled call as an RPCError wrapping
/// the CancellationError; when that arrives while the loader's task is alive —
/// list loads run in `SingleFlightLoadGate`'s own task — the daemon connection
/// went away under the call, which is a failure the view must show and offer
/// to retry. Only the report is noise, and `ErrorReporting.send` drops that.
@MainActor
final class LoadPhaseTests: XCTestCase {
    private let transportCancellation = RPCError(
        code: .unknown,
        message: "The transport threw an unexpected error.",
        cause: CancellationError()
    )

    func testATransportCancellationWithALiveTaskStaysAFailure() {
        var phase = LoadPhase.waiting
        let isRefresh = phase.beginLoading()

        XCTAssertFalse(phase.cancelLoading(for: transportCancellation, retainingLoadedContent: isRefresh))
        XCTAssertEqual(phase, .loading)
        XCTAssertNil(phase.fail("gone", retainingLoadedContent: isRefresh))
        XCTAssertEqual(phase, .failed("gone"))
    }

    func testTheTasksOwnCancellationAbandonsTheLoad() {
        var phase = LoadPhase.loaded
        let isRefresh = phase.beginLoading()

        XCTAssertTrue(phase.cancelLoading(for: CancellationError(), retainingLoadedContent: isRefresh))
        XCTAssertEqual(phase, .loaded)
    }
}
