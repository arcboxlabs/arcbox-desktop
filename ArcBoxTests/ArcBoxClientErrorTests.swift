import GRPCCore
import XCTest

@testable import ArcBoxClient

final class ArcBoxClientErrorTests: XCTestCase {

    // MARK: - userMessage

    func testSurfacesDaemonReasonForInternalError() {
        let error = RPCError(
            code: .internalError,
            message: "invalid state: machine 'ubuntu' is already running"
        )
        XCTAssertEqual(
            ArcBoxClient.userMessage(for: error),
            "invalid state: machine 'ubuntu' is already running"
        )
    }

    func testCannedCopyForConnectivityCodes() {
        XCTAssertEqual(
            ArcBoxClient.userMessage(for: RPCError(code: .unavailable, message: "broken pipe")),
            "Cannot reach ArcBox daemon. Is it running?"
        )
        XCTAssertEqual(
            ArcBoxClient.userMessage(for: RPCError(code: .deadlineExceeded, message: "")),
            "Operation timed out. The daemon may be busy."
        )
    }

    func testFallsBackToCodeWhenMessageEmpty() {
        let error = RPCError(code: .unknown, message: "   ")
        XCTAssertTrue(ArcBoxClient.userMessage(for: error).contains("daemon reported"))
    }

    // MARK: - rpcMessage

    func testRPCMessageMatchesReasonCaseInsensitively() {
        let error = RPCError(code: .internalError, message: "machine 'x' is Already Running")
        XCTAssertTrue(ArcBoxClient.rpcMessage(error, contains: "already running"))
        XCTAssertFalse(ArcBoxClient.rpcMessage(error, contains: "not running"))
    }

    func testRPCMessageIgnoresNonGRPCErrors() {
        struct Other: Error {}
        XCTAssertFalse(ArcBoxClient.rpcMessage(Other(), contains: "already running"))
    }
}
