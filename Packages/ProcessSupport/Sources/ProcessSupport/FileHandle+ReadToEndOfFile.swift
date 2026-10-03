import Foundation

extension FileHandle {
    /// Reads until EOF without blocking a thread: chunks arrive on the readability callback.
    /// Stops reading and throws `ProcessOutputLimitExceeded` once more than `limit` bytes have
    /// arrived; cancellation stops it too and returns what has arrived so far.
    public func readToEndOfFile(limit: Int) async throws -> Data {
        let (chunks, feed) = AsyncStream<Data>.makeStream()
        readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                feed.finish()
            } else {
                feed.yield(chunk)
            }
        }
        defer { readabilityHandler = nil }
        var data = Data()
        for await chunk in chunks {
            data.append(chunk)
            if data.count > limit {
                throw ProcessOutputLimitExceeded(limit: limit)
            }
        }
        return data
    }
}
