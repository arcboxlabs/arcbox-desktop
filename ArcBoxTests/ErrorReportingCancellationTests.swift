import ArcBoxClient
import Foundation
import GRPCCore
import XCTest

@testable import ArcBox

/// Pins the sink's cancellation guard: a cancelled call is teardown, not a
/// defect, and must not become a Sentry event in any of the shapes it arrives
/// in — while every other error still goes through.
@MainActor
final class ErrorReportingCancellationTests: XCTestCase {
    /// Sentry issue ARCBOX-DESKTOP-SWIFT-2: grpc-swift wraps a CancellationError
    /// thrown inside the call's task group, so the caller never sees a bare one.
    func testTheTransportWrappedCancellationIsDropped() {
        let error = RPCError(
            code: .unknown,
            message: "The transport threw an unexpected error.",
            cause: CancellationError()
        )
        XCTAssertFalse(ErrorReporting.send(error, tags: ["operation": "list"]))
    }

    func testEveryOtherCancellationShapeIsDropped() {
        XCTAssertFalse(ErrorReporting.send(CancellationError(), tags: [:]))
        XCTAssertFalse(ErrorReporting.send(RPCError(code: .cancelled, message: ""), tags: [:]))
        XCTAssertFalse(ErrorReporting.send(URLError(.cancelled), tags: [:]))
        XCTAssertFalse(
            ErrorReporting.send(
                NSError(domain: "ArcBoxTests", code: 1, userInfo: [NSUnderlyingErrorKey: CancellationError()]),
                tags: [:]))
    }

    func testFailuresStillReachSentry() {
        XCTAssertTrue(
            ErrorReporting.send(RPCError(code: .unavailable, message: "connection refused"), tags: [:]))
        XCTAssertTrue(ErrorReporting.send(NSError(domain: "ArcBoxTests", code: 42), tags: [:]))
    }
}
