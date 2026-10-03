import Foundation
import GRPCCore

extension Error {
    /// Whether this error says that work was cancelled rather than that it failed.
    ///
    /// Cancellation reaches a caller in more than one shape. The task's own
    /// `CancellationError` is the obvious one, but a cancelled gRPC call arrives
    /// as an `RPCError` — either with status `.cancelled`, or as the `unknown:
    /// "The transport threw an unexpected error."` error grpc-swift synthesises
    /// around a `CancellationError` thrown inside the call's own task group,
    /// which is why `catch is CancellationError` never sees it and the caller's
    /// `Task.isCancelled` is false. A URLSession task reports `URLError.cancelled`,
    /// and any of these may sit under an `NSError` as its underlying error.
    ///
    /// Every shape means the same thing to a crash reporter: a view
    /// disappeared, the daemon restarted, the app is quitting — none is worth
    /// an error report. Control flow is a different question. A call site keys
    /// its own cancellation handling on the task (`Task.isCancelled`, a bare
    /// `CancellationError`); a cancellation the transport manufactured while
    /// the task is alive means the connection went away under the call, which
    /// the UI treats like any other transport failure: show it, offer a retry.
    public var isCancellation: Bool {
        if self is CancellationError {
            return true
        }
        if let rpcError = self as? RPCError {
            return rpcError.code == .cancelled || rpcError.cause?.isCancellation == true
        }
        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }
        if let underlying = (self as NSError).userInfo[NSUnderlyingErrorKey] as? any Error {
            return underlying.isCancellation
        }
        return false
    }
}
