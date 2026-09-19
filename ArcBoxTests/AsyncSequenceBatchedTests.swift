import XCTest

@testable import ArcBox

final class AsyncSequenceBatchedTests: XCTestCase {
    private static let interval = Duration.milliseconds(50)

    /// The point of batching: a burst arrives as one element, not as one each.
    func testABurstArrivesAsASingleBatch() async throws {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        for value in 1...5 { continuation.yield(value) }
        continuation.finish()

        var batches: [[Int]] = []
        for try await batch in stream.batched(every: Self.interval) { batches.append(batch) }

        XCTAssertEqual(batches, [[1, 2, 3, 4, 5]])
    }

    /// A stream that goes quiet must not strand what it already sent, which is the common
    /// case: a container logs a line or two and then says nothing for minutes.
    func testAQuietStreamStillDeliversWithinOneInterval() async throws {
        let stream = AsyncStream<Int> { continuation in
            Task {
                continuation.yield(1)
                try? await Task.sleep(for: Self.interval * 4)
                continuation.yield(2)
                continuation.finish()
            }
        }

        var batches: [[Int]] = []
        for try await batch in stream.batched(every: Self.interval) { batches.append(batch) }

        XCTAssertEqual(batches, [[1], [2]])
    }

    func testAnEmptyStreamYieldsNothing() async throws {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        continuation.finish()

        var batches: [[Int]] = []
        for try await batch in stream.batched(every: Self.interval) { batches.append(batch) }

        XCTAssertTrue(batches.isEmpty)
    }

    /// Whatever the source sent before it failed is worth showing, and the failure still
    /// has to surface so the tab can report it.
    func testAFailureDeliversTheBufferedElementsAndThenThrows() async throws {
        struct Boom: Error {}
        let (stream, continuation) = AsyncThrowingStream<Int, any Error>.makeStream()
        continuation.yield(1)
        continuation.yield(2)
        continuation.finish(throwing: Boom())

        var batches: [[Int]] = []
        do {
            for try await batch in stream.batched(every: Self.interval) { batches.append(batch) }
            XCTFail("Expected the source's failure to surface")
        } catch is Boom {
            XCTAssertEqual(batches, [[1, 2]])
        }
    }
}
