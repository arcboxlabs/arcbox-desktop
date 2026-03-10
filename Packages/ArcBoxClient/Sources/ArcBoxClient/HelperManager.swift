import ServiceManagement
import Foundation

public enum HelperError: LocalizedError {
    case connectionFailed
    case versionMismatch(Int)
    case requiresApproval

    public var errorDescription: String? {
        switch self {
        case .connectionFailed:           return "Failed to connect to helper"
        case .versionMismatch(let v):     return "Helper version \(v) is outdated, please restart ArcBox"
        case .requiresApproval:           return "Helper requires approval in System Settings"
        }
    }
}

@Observable
@MainActor
public final class HelperManager {
    public private(set) var isInstalled = false
    public private(set) var requiresApproval = false

    public init() {}

    // MARK: - Registration

    /// Registers the helper daemon via SMAppService.
    /// First call shows a one-time system approval dialog.
    /// Subsequent calls are idempotent and return immediately.
    public func register() async throws {
        let service = SMAppService.daemon(plistName: "io.arcbox.desktop.helper.plist")
        switch service.status {
        case .enabled:
            isInstalled = true
        case .notRegistered, .notFound:
            try service.register()
            isInstalled = true
        case .requiresApproval:
            requiresApproval = true
            throw HelperError.requiresApproval
        @unknown default:
            break
        }

        let version = await getVersion()
        if version < kArcBoxHelperProtocolVersion {
            throw HelperError.versionMismatch(version)
        }
    }

    /// Opens System Settings -> General -> Login Items for manual approval.
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Public Operations

    public func setupDockerSocket(socketPath: String) async throws {
        try await call { $0.setupDockerSocket(socketPath: socketPath, reply: $1) }
    }

    public func teardownDockerSocket() async throws {
        try await call { $0.teardownDockerSocket(reply: $1) }
    }

    public func installCLITools(appBundlePath: String) async throws {
        try await call { $0.installCLITools(appBundlePath: appBundlePath, reply: $1) }
    }

    public func uninstallCLITools() async throws {
        try await call { $0.uninstallCLITools(reply: $1) }
    }

    public func setupDNSResolver(domain: String = "arcbox.local", port: Int = 5553) async throws {
        try await call { $0.setupDNSResolver(domain: domain, port: port, reply: $1) }
    }

    public func teardownDNSResolver(domain: String = "arcbox.local") async throws {
        try await call { $0.teardownDNSResolver(domain: domain, reply: $1) }
    }

    // MARK: - Private: XPC

    private func getVersion() async -> Int {
        await withXPCConnection { p, finish in
            p.getVersion { finish($0) }
        } onFailure: { 0 }
    }

    /// Thin wrapper: all error-reply operations go through withXPCConnection.
    private func call(
        _ operation: @escaping (ArcBoxHelperProtocol, @escaping (NSError?) -> Void) -> Void
    ) async throws {
        try await withXPCConnection { p, finish in
            operation(p) { finish($0) }
        }
    }

    /// Unified XPC connection helper for error-reply operations.
    ///
    /// Guarantees:
    /// - Connection is held alive for the full duration of the async continuation.
    /// - Continuation resumes exactly once via `resumed` flag — safe against both
    ///   normal reply, remoteObjectProxy error handler, invalidationHandler, and
    ///   interruptionHandler all potentially firing.
    /// - Connection is invalidated immediately after resuming.
    private func withXPCConnection(
        _ body: @escaping (ArcBoxHelperProtocol, @escaping (NSError?) -> Void) -> Void
    ) async throws {
        let conn = makeConnection()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            func finish(_ result: Result<Void, Error>) {
                guard !resumed else { return }
                resumed = true
                conn.invalidate()
                switch result {
                case .success:          cont.resume()
                case .failure(let e):   cont.resume(throwing: e)
                }
            }
            conn.invalidationHandler  = { finish(.failure(HelperError.connectionFailed)) }
            conn.interruptionHandler  = { finish(.failure(HelperError.connectionFailed)) }
            let proxy = conn.remoteObjectProxyWithErrorHandler { finish(.failure($0)) }
            guard let p = proxy as? ArcBoxHelperProtocol else {
                finish(.failure(HelperError.connectionFailed)); return
            }
            body(p) { nsError in
                if let e = nsError { finish(.failure(e)) } else { finish(.success(())) }
            }
        }
    }

    /// Generic variant used by getVersion() to return a value instead of Void.
    private func withXPCConnection<T: Sendable>(
        _ body: @escaping (ArcBoxHelperProtocol, @escaping (T) -> Void) -> Void,
        onFailure: @escaping @Sendable () -> T
    ) async -> T {
        let conn = makeConnection()
        return await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            nonisolated(unsafe) var resumed = false
            func finish(_ value: T) {
                guard !resumed else { return }
                resumed = true
                conn.invalidate()
                cont.resume(returning: value)
            }
            conn.invalidationHandler  = { finish(onFailure()) }
            conn.interruptionHandler  = { finish(onFailure()) }
            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in finish(onFailure()) }
            guard let p = proxy as? ArcBoxHelperProtocol else {
                finish(onFailure()); return
            }
            body(p) { finish($0) }
        }
    }

    private nonisolated func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: "io.arcbox.desktop.helper")
        conn.remoteObjectInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
        conn.resume()
        return conn
    }
}
