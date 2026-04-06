import Foundation
@preconcurrency import Sentry

/// Lightweight performance measurement wrapper.
///
/// Wraps an async operation in a Sentry span and optionally emits a PostHog
/// event when the call exceeds a latency threshold.
///
/// Usage:
/// ```swift
/// let containers = try await Perf.measure("container.list_docker") {
///     try await docker.api.ContainerList(.init(query: .init(all: true)))
/// }
/// ```
nonisolated enum Perf {

    /// Measure an async operation.
    ///
    /// - Parameters:
    ///   - operation: Human-readable operation name (e.g. "container.list_grpc").
    ///   - slowThresholdMs: Emit a PostHog event when duration exceeds this (default 500ms).
    ///   - body: The async work to measure.
    /// - Returns: The result of `body`.
    static func measure<T: Sendable>(
        _ operation: String,
        slowThresholdMs: Int = 500,
        body: @Sendable () async throws -> T
    ) async rethrows -> T {
        let span = SentrySDK.span?.startChild(operation: operation)
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let result = try await body()
            let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            span?.finish(status: .ok)
            if ms > slowThresholdMs {
                Analytics.capture(
                    .perfSlowCall,
                    properties: [
                        "operation": operation,
                        "duration_ms": ms,
                    ])
            }
            return result
        } catch {
            span?.finish(status: .internalError)
            throw error
        }
    }
}
