import Foundation

/// Retry policy for one watch stream: how long to wait before reconnecting, and whether a
/// failure is worth reporting.
///
/// Both answers start over only after a stream that stayed up. A delivered snapshot is not
/// evidence of that: the initial LIST can succeed on every attempt while the watch behind
/// it never establishes, and starting over on each one would hold a broken stream at the
/// minimum delay, reporting the same cause, forever.
nonisolated struct WatchRetry {
    static let minimumDelay = Duration.seconds(2)
    static let maximumDelay = Duration.seconds(15)
    /// How long a stream must survive for its eventual failure to count as a new outage.
    static let stableLifetime = Duration.seconds(30)

    struct Attempt: Equatable {
        /// How long to wait before reconnecting.
        let delay: Duration
        /// Whether this outage has not reported the failure's cause yet.
        let isNewCause: Bool
    }

    /// Consecutive failures in the current outage.
    private(set) var failures = 0
    private var reportedCauses = Set<String>()

    /// Record a stream that ended with `error` (nil if it just finished) after `lifetime`
    /// (nil if it never started).
    ///
    /// A cause is the error's bridged domain and code, nothing finer: a URL error's
    /// `userInfo` names the failing URL, whose `resourceVersion` moves between attempts.
    mutating func recordFailure(_ error: (any Error)?, streamLifetime lifetime: Duration?) -> Attempt {
        if let lifetime, lifetime >= Self.stableLifetime {
            failures = 0
            reportedCauses.removeAll()
        }
        failures += 1

        let isNewCause =
            error.map { error in
                let error = error as NSError
                return reportedCauses.insert("\(error.domain)#\(error.code)").inserted
            } ?? false
        let delay = min(Self.minimumDelay * Double(1 << min(failures - 1, 3)), Self.maximumDelay)
        return Attempt(delay: delay, isNewCause: isNewCause)
    }
}
