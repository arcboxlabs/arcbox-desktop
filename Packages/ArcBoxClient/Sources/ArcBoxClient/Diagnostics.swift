import Synchronization

/// A breadcrumb recording something the client observed, kept for whatever
/// failure is diagnosed later.
public struct DiagnosticBreadcrumb: Sendable {
    public enum Level: Sendable {
        case info
        case warning
        case error
    }

    public let level: Level
    public let category: String
    public let message: String

    public init(level: Level, category: String, message: String) {
        self.level = level
        self.category = category
        self.message = message
    }
}

/// Where this package's diagnostics go.
///
/// ArcBoxClient reports what it sees but owns no crash reporter: the host app
/// installs a sink over whatever backend it already runs, which is what keeps
/// a gRPC client package from linking one. `ArcBox` implements this over
/// Sentry; tests and any other consumer get the no-op default.
public protocol DiagnosticsSink: Sendable {
    func add(_ breadcrumb: DiagnosticBreadcrumb)
    func capture(_ error: Error, tags: [String: String])
}

/// The client's diagnostics channel, sibling to ``ClientLog``.
///
/// Diagnostics emitted before ``install(_:)`` — or when the host installs
/// nothing — are dropped.
public enum ClientDiagnostics {
    private static let sink = Mutex<(any DiagnosticsSink)?>(nil)

    /// Route this package's diagnostics to `sink`. Call once during startup.
    public static func install(_ sink: any DiagnosticsSink) {
        Self.sink.withLock { $0 = sink }
    }

    // Read under the lock, deliver outside it: a sink is host code and may do
    // real work, which is not something to hold a global lock across.
    static func add(_ breadcrumb: DiagnosticBreadcrumb) {
        sink.withLock { $0 }?.add(breadcrumb)
    }

    static func capture(_ error: Error, tags: [String: String]) {
        sink.withLock { $0 }?.capture(error, tags: tags)
    }
}
