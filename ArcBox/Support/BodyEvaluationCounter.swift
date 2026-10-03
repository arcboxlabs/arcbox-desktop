import SwiftUI

#if DEBUG
    /// Counts `body` evaluations of the views the relayout regression tests pin.
    ///
    /// A view records itself by applying `recordingBodyEvaluation(of: Self.self)`
    /// to the outermost view of its `body`. A test resets the counter, drives a
    /// hot update N times, and asserts that a view which must sit outside that
    /// update's invalidation scope was evaluated 0 times.
    enum BodyEvaluationCounter {
        private static var counts: [ObjectIdentifier: Int] = [:]

        static func record(_ view: Any.Type) {
            counts[ObjectIdentifier(view), default: 0] += 1
        }

        static func count(of view: Any.Type) -> Int {
            counts[ObjectIdentifier(view)] ?? 0
        }

        static func reset() {
            counts = [:]
        }
    }
#endif

extension View {
    /// Records one evaluation of `view`'s body in `BodyEvaluationCounter`.
    ///
    /// Apply it to the outermost view of a `body`: the call then runs each time
    /// the body is evaluated and nowhere else. Release builds return `self`
    /// and record nothing.
    func recordingBodyEvaluation(of view: Any.Type) -> Self {
        #if DEBUG
            BodyEvaluationCounter.record(view)
        #endif
        return self
    }
}
