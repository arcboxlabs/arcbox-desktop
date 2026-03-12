import Foundation
import ServiceManagement

public enum HelperError: LocalizedError {
    case connectionFailed
    case versionMismatch(Int)
    case requiresApproval

    public var errorDescription: String? {
        switch self {
        case .connectionFailed: return "Failed to connect to helper"
        case .versionMismatch(let v):
            return "Helper version \(v) is outdated, please restart ArcBox"
        case .requiresApproval: return "Helper requires approval in System Settings"
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
            // Best-effort re-register to update helper binary path.
            try? service.register()
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

        #if DEBUG
        // Skip version check when already enabled — during development,
        // rebuilds change the CDHash but launchd caches the old LWCR.
        // Use `sudo sfltool resetbtm` in Terminal to clear stale state.
        if service.status == .enabled { return }
        #endif

        let version = await getVersion()
        if version == 0 {
            throw HelperError.connectionFailed
        }
        if version < kArcBoxHelperProtocolVersion {
            throw HelperError.versionMismatch(version)
        }
    }

    /// Registers the helper, automatically retrying if approval is needed.
    /// Opens System Settings and polls until the user approves (up to 2 minutes).
    public func registerWithRetry() async throws {
        do {
            try await register()
            return
        } catch HelperError.requiresApproval {
            print("[Helper] Requires approval — opening System Settings")
            openSystemSettings()
        }

        // Poll for approval (every 2s, up to 60 attempts = 2 min).
        let service = SMAppService.daemon(plistName: "io.arcbox.desktop.helper.plist")
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(2))
            if service.status != .requiresApproval {
                try await register()
                return
            }
        }
        throw HelperError.requiresApproval
    }

    /// Opens System Settings -> General -> Login Items for manual approval.
    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Public Operations

    public func setupDockerSocket(socketPath: String) async throws {
        try await call(.setupDockerSocket(socketPath: socketPath))
    }

    public func teardownDockerSocket() async throws {
        try await call(.teardownDockerSocket)
    }

    public func installCLITools(appBundlePath: String) async throws {
        try await call(.installCLITools(appBundlePath: appBundlePath))
    }

    public func uninstallCLITools() async throws {
        try await call(.uninstallCLITools)
    }

    public func setupDNSResolver(domain: String = "arcbox.local", port: Int = 5553) async throws {
        try await call(.setupDNSResolver(domain: domain, port: port))
    }

    public func teardownDNSResolver(domain: String = "arcbox.local") async throws {
        try await call(.teardownDNSResolver(domain: domain))
    }

    // MARK: - Private: XPC

    private enum HelperOperation: Sendable {
        case setupDockerSocket(socketPath: String)
        case teardownDockerSocket
        case installCLITools(appBundlePath: String)
        case uninstallCLITools
        case setupDNSResolver(domain: String, port: Int)
        case teardownDNSResolver(domain: String)
    }

    private nonisolated func getVersion() async -> Int {
        await withXPCConnection(
            { p, finish in
                p.getVersion { finish($0) }
            }, onFailure: 0)
    }

    /// Thin wrapper: all error-reply operations go through withXPCConnection.
    private nonisolated func call(_ operation: HelperOperation) async throws {
        try await withXPCConnection { p, finish in
            switch operation {
            case .setupDockerSocket(let socketPath):
                p.setupDockerSocket(socketPath: socketPath, reply: finish)
            case .teardownDockerSocket:
                p.teardownDockerSocket(reply: finish)
            case .installCLITools(let appBundlePath):
                p.installCLITools(appBundlePath: appBundlePath, reply: finish)
            case .uninstallCLITools:
                p.uninstallCLITools(reply: finish)
            case .setupDNSResolver(let domain, let port):
                p.setupDNSResolver(domain: domain, port: port, reply: finish)
            case .teardownDNSResolver(let domain):
                p.teardownDNSResolver(domain: domain, reply: finish)
            }
        }
    }

    /// XPC timeout in seconds. Prevents infinite hangs when the helper can't spawn
    /// (e.g. stale LWCR after rebuild causes xpcproxy EX_CONFIG).
    private nonisolated static let xpcTimeout: TimeInterval = 10

    /// Thread-safe one-shot gate for continuation resume.
    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func trySetResumed() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }

    /// Unified XPC connection helper for error-reply operations.
    ///
    /// Guarantees:
    /// - Continuation resumes exactly once — protected by NSLock against concurrent
    ///   callbacks from XPC error handler, invalidation handler, and timeout.
    /// - finish() never calls conn.invalidate() — eliminates re-entrant handler chains.
    /// - Connection cleanup happens via defer after the continuation resumes.
    private nonisolated func withXPCConnection(
        _ body: @escaping (ArcBoxHelperProtocol, @escaping (NSError?) -> Void) -> Void
    ) async throws {
        let conn = makeConnection()
        defer { conn.invalidate() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            func finish(_ result: Result<Void, Error>) {
                guard gate.trySetResumed() else { return }
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            func finishOnMain(_ result: Result<Void, Error>) {
                if Thread.isMainThread {
                    finish(result)
                } else {
                    DispatchQueue.main.async { finish(result) }
                }
            }
            conn.invalidationHandler = { finishOnMain(.failure(HelperError.connectionFailed)) }
            conn.interruptionHandler = { finishOnMain(.failure(HelperError.connectionFailed)) }

            // Timeout fails directly; defer handles connection cleanup after resume.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.xpcTimeout) {
                finishOnMain(.failure(HelperError.connectionFailed))
            }

            let proxy = conn.remoteObjectProxyWithErrorHandler { finishOnMain(.failure($0)) }
            guard let p = proxy as? ArcBoxHelperProtocol else {
                finishOnMain(.failure(HelperError.connectionFailed))
                return
            }
            body(p) { nsError in
                if let e = nsError { finishOnMain(.failure(e)) } else { finishOnMain(.success(())) }
            }
        }
    }

    /// Generic variant used by getVersion() to return a value instead of Void.
    private nonisolated func withXPCConnection<T: Sendable>(
        _ body: @escaping (ArcBoxHelperProtocol, @escaping (T) -> Void) -> Void,
        onFailure failureValue: T
    ) async -> T {
        let conn = makeConnection()
        defer { conn.invalidate() }
        return await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            let gate = ResumeGate()
            func finish(_ value: T) {
                guard gate.trySetResumed() else { return }
                cont.resume(returning: value)
            }
            func finishOnMain(_ value: T) {
                if Thread.isMainThread {
                    finish(value)
                } else {
                    DispatchQueue.main.async { finish(value) }
                }
            }
            conn.invalidationHandler = { finishOnMain(failureValue) }
            conn.interruptionHandler = { finishOnMain(failureValue) }

            // Timeout fails directly; defer handles connection cleanup after resume.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.xpcTimeout) {
                finishOnMain(failureValue)
            }

            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in finishOnMain(failureValue) }
            guard let p = proxy as? ArcBoxHelperProtocol else {
                finishOnMain(failureValue)
                return
            }
            body(p) { finishOnMain($0) }
        }
    }

    private nonisolated func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(
            machServiceName: "io.arcbox.desktop.helper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
        conn.resume()
        return conn
    }
}
