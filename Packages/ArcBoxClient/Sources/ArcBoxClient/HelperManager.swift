import Foundation
import OSLog
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

    private var monitorTask: Task<Void, Never>?

    public init() {}

    // MARK: - Monitoring

    /// Periodically checks if login item approval has been revoked.
    /// Sets `requiresApproval = true` when the user disables the login item.
    public func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let service = SMAppService.daemon(plistName: "com.arcboxlabs.desktop.helper.plist")
                let status = service.status
                if status == .requiresApproval, !self.requiresApproval {
                    self.requiresApproval = true
                    self.isInstalled = false
                    ClientLog.helper.warning("Login item approval revoked")
                } else if status == .enabled, self.requiresApproval {
                    self.requiresApproval = false
                    self.isInstalled = true
                    ClientLog.helper.info("Login item approval restored")
                }
            }
        }
    }

    /// Stop periodic monitoring.
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Registration

    /// Registers the helper daemon via SMAppService.
    /// First call shows a one-time system approval dialog.
    /// Subsequent calls are idempotent and return immediately.
    public func register() async throws {
        let service = SMAppService.daemon(plistName: "com.arcboxlabs.desktop.helper.plist")

        switch service.status {
        case .enabled:
            // Force re-register to pick up updated helper binary after app
            // update. Without unregister(), launchd keeps the old process and
            // the new binary is never loaded.
            try? await service.unregister()
            try service.register()
            requiresApproval = false
        case .notRegistered, .notFound:
            try service.register()
            // On macOS 13+, register() may succeed but the service still
            // needs user approval in System Settings → Login Items. Re-check
            // status so registerWithRetry() can open Settings and poll.
            if service.status == .requiresApproval {
                requiresApproval = true
                throw HelperError.requiresApproval
            }
            requiresApproval = false
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
        if service.status == .enabled {
            isInstalled = true
            return
        }
        #endif

        let version = await getVersion()
        if version == 0 {
            isInstalled = false
            throw HelperError.connectionFailed
        }
        if version < kArcBoxHelperProtocolVersion {
            isInstalled = false
            throw HelperError.versionMismatch(version)
        }
        isInstalled = true
    }

    /// Registers the helper, automatically retrying if approval is needed.
    /// Opens System Settings and polls until the user approves (up to 2 minutes).
    public func registerWithRetry() async throws {
        do {
            try await register()
            return
        } catch HelperError.requiresApproval {
            ClientLog.helper.notice("Requires approval — opening System Settings")
            openSystemSettings()
        }

        // Poll for approval (every 2s, up to 60 attempts = 2 min).
        let service = SMAppService.daemon(plistName: "com.arcboxlabs.desktop.helper.plist")
        for _ in 0..<StartupConstants.helperApprovalMaxAttempts {
            try await Task.sleep(for: StartupConstants.helperApprovalPollInterval)
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

    public func addRouteGateway(subnet: String, gateway: String) async throws {
        try await call(.addRouteGateway(subnet: subnet, gateway: gateway))
    }

    public func addRouteInterface(subnet: String, iface: String) async throws {
        try await call(.addRouteInterface(subnet: subnet, iface: iface))
    }

    public func removeRouteGateway(subnet: String, gateway: String) async throws {
        try await call(.removeRouteGateway(subnet: subnet, gateway: gateway))
    }

    public func removeRouteInterface(subnet: String, iface: String) async throws {
        try await call(.removeRouteInterface(subnet: subnet, iface: iface))
    }

    // MARK: - Private: XPC

    private enum HelperOperation: Sendable {
        case setupDockerSocket(socketPath: String)
        case teardownDockerSocket
        case installCLITools(appBundlePath: String)
        case uninstallCLITools
        case setupDNSResolver(domain: String, port: Int)
        case teardownDNSResolver(domain: String)
        case addRouteGateway(subnet: String, gateway: String)
        case addRouteInterface(subnet: String, iface: String)
        case removeRouteGateway(subnet: String, gateway: String)
        case removeRouteInterface(subnet: String, iface: String)
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
            case .addRouteGateway(let subnet, let gateway):
                p.addRouteGateway(subnet: subnet, gateway: gateway, reply: finish)
            case .addRouteInterface(let subnet, let iface):
                p.addRouteInterface(subnet: subnet, iface: iface, reply: finish)
            case .removeRouteGateway(let subnet, let gateway):
                p.removeRouteGateway(subnet: subnet, gateway: gateway, reply: finish)
            case .removeRouteInterface(let subnet, let iface):
                p.removeRouteInterface(subnet: subnet, iface: iface, reply: finish)
            }
        }
    }

    /// XPC timeout in seconds. Prevents infinite hangs when the helper can't spawn
    /// (e.g. stale LWCR after rebuild causes xpcproxy EX_CONFIG).
    private nonisolated static let xpcTimeout: TimeInterval = StartupConstants.xpcTimeout

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
            machServiceName: "com.arcboxlabs.desktop.helper", options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
        conn.resume()
        return conn
    }
}
