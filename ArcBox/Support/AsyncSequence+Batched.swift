import Foundation

extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// Groups elements into batches, handing one over at most every `interval`.
    ///
    /// For a SwiftUI list, the cost of an append is the whole list, not the element: a
    /// container logging steadily made the tab rebuild thousands of rows hundreds of times
    /// a second. Batching trades up to `interval` of latency for one rebuild per tick. A
    /// quiet stream still lands within `interval`, and whatever is buffered when the source
    /// ends or fails is handed over before the batches finish.
    nonisolated func batched(every interval: Duration) -> AsyncThrowingStream<[Element], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let buffer = Batch<Element>()
                do {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for try await element in self { await buffer.append(element) }
                        }
                        group.addTask {
                            while true {
                                try await Task.sleep(for: interval)
                                let batch = await buffer.drain()
                                if !batch.isEmpty { continuation.yield(batch) }
                            }
                        }
                        defer { group.cancelAll() }
                        // The pump is the only task that finishes on its own.
                        try await group.next()
                    }
                    await Self.flush(buffer, into: continuation)
                    continuation.finish()
                } catch {
                    await Self.flush(buffer, into: continuation)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private static func flush(
        _ buffer: Batch<Element>, into continuation: AsyncThrowingStream<[Element], any Error>.Continuation
    ) async {
        let tail = await buffer.drain()
        if !tail.isEmpty { continuation.yield(tail) }
    }
}

private actor Batch<Element: Sendable> {
    private var elements: [Element] = []

    func append(_ element: Element) {
        elements.append(element)
    }

    func drain() -> [Element] {
        defer { elements.removeAll(keepingCapacity: true) }
        return elements
    }
}
