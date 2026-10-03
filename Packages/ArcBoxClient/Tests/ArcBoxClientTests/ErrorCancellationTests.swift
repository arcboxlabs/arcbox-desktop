import ArcBoxClient
import Foundation
import GRPCCore
import Testing

@Suite struct ErrorCancellationTests {
    /// The shape behind Sentry issue ARCBOX-DESKTOP-SWIFT-2: grpc-swift wraps a
    /// `CancellationError` from the call's task group in an `unknown` RPCError.
    @Test func transportWrappedCancellationIsCancellation() {
        let error = RPCError(
            code: .unknown,
            message: "The transport threw an unexpected error.",
            cause: CancellationError()
        )
        #expect(error.isCancellation)
    }

    @Test func plainCancellationErrorIsCancellation() {
        #expect(CancellationError().isCancellation)
    }

    @Test func cancelledStatusIsCancellation() {
        #expect(RPCError(code: .cancelled, message: "").isCancellation)
    }

    @Test func cancelledURLErrorIsCancellation() {
        #expect(URLError(.cancelled).isCancellation)
        #expect(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled).isCancellation)
    }

    @Test func cancellationUnderAnNSErrorIsCancellation() {
        let error = NSError(
            domain: "ArcBoxTests",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: URLError(.cancelled)]
        )
        #expect(error.isCancellation)
    }

    @Test func cancellationNestedTwoCausesDeepIsCancellation() {
        let inner = RPCError(code: .unknown, message: "transport", cause: CancellationError())
        let outer = RPCError(code: .internalError, message: "retry gave up", cause: inner)
        #expect(outer.isCancellation)
    }

    @Test func failuresAreNotCancellation() {
        #expect(!RPCError(code: .unavailable, message: "connection refused").isCancellation)
        #expect(!RPCError(code: .unknown, message: "The transport threw an unexpected error.").isCancellation)
        #expect(!URLError(.timedOut).isCancellation)
        #expect(!NSError(domain: "ArcBoxTests", code: 7).isCancellation)
        struct Other: Error {}
        #expect(!Other().isCancellation)
    }
}
