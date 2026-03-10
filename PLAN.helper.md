# ArcBox Privileged Helper 实施计划

## 背景

ArcBox 需要执行三类特权操作，这些操作无法在普通用户权限下完成，因此需要一个以 root 运行的 privileged helper：

| 操作 | 目标路径 | 为何需要 root |
|------|----------|--------------|
| Docker socket 软链接 | `/var/run/docker.sock` → `~/.arcbox/run/docker.sock` | `/var/run` 归 root 所有 |
| CLI 工具安装 | `/usr/local/bin/abctl` | 系统目录写入 |
| DNS Resolver 配置 | `/etc/resolver/arcbox.local` | `/etc/resolver/` 归 root 所有 |

> **标识符处理**：
> - **`PRODUCT_BUNDLE_IDENTIFIER`**：写死 `com.arcbox.arcbox-desktop-swift`（plist、Swift 代码中均直接使用）
> - **`DEVELOPMENT_TEAM`**：走 `Local.xcconfig`（已有，gitignored）→ Xcode build setting
>   - Helper 自身 Info.plist：写 `$(DEVELOPMENT_TEAM)`，Xcode **会**展开（这是 target 自己的 Info.plist）
>   - LaunchDaemon plist：Apple **不会**在 Copy Files phase 展开 `$(VAR)`，
>     因此用 Run Script build phase + `sed` 替换占位符 `__DEVELOPMENT_TEAM__` 后输出到 bundle
>   - Swift 代码中：Helper 从自身 `Bundle.main.object(forInfoDictionaryKey: "ArcBoxTeamID")` 读取
> - `Local.xcconfig.example`（已有）提供模板：`DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE`

## 架构选型：SMAppService（macOS 13+）

不使用 OrbStack/Docker Desktop 采用的 **SMJobBless**（已在 macOS 13 废弃），改用 **SMAppService**。

| 维度 | SMJobBless | SMAppService（本方案） |
|------|-----------|----------------------|
| macOS 状态 | 废弃（macOS 13+） | 推荐方案 |
| helper 二进制位置 | `/Library/PrivilegedHelperTools/`（系统级，全局残留） | `ArcBox.app/Contents/Library/HelperTools/`（bundle 内） |
| 卸载清理 | **残留系统**，需手动 `launchctl` 清理 | 随 `.app` 删除**自动注销** |
| Launch Constraints | 需手动配置 `SMAuthorizedClients` | `AssociatedBundleIdentifiers` + `SpawnConstraint` |
| 安装复杂度 | 高（两个独立 bundle 的 code signing 协商） | 低（`SMAppService.register()` 一行） |

## Bundle 结构

```
ArcBox.app/
└── Contents/
    ├── MacOS/
    │   ├── ArcBox                              # 主 App
    │   └── bin/
    │       └── abctl                           # CLI binary（已有）
    ├── Library/
    │   ├── LaunchDaemons/
    │   │   └── io.arcbox.desktop.helper.plist  # launchd 配置（新增）
    │   └── HelperTools/
    │       └── ArcBoxHelper                    # 特权 daemon 二进制（新增）
    └── Info.plist
```

## 安全设计原则

1. **最小特权**：helper 只暴露 3 个操作，不提供 shell 执行接口
2. **路径验证不依赖运行时 home 目录**：helper 以 root 运行，`homeDirectoryForCurrentUser` 是 `/var/root`，
   所有路径校验使用 regex 匹配 `/Users/<name>/` 模式，不查询 FileManager
3. **非破坏性 socket 管理**：`setupDockerSocket` 检查 `/var/run/docker.sock` 现有状态，
   仅当路径不存在、或现有 symlink 目标本身就是 ArcBox 路径时才替换；
   任何非 ArcBox symlink（无论目标存活与否）均返回 error，不触碰
4. **只创建软链接**：不向系统目录写入任意二进制内容
5. **调用方验证**：`NSXPCConnection.setCodeSigningRequirement` + plist `SpawnConstraint` 双重校验
6. **XPC 连接生命周期**：每次调用在 `call()` 内创建并持有连接，reply 返回后立即 `invalidate()`，
   不存在连接提前释放导致 continuation 卡死的问题
7. **幂等操作**：每个操作重复调用安全，不产生副作用
8. **按需启动**：不设 `RunAtLoad`，daemon 仅在 XPC 请求到达时由 launchd 唤醒

---

## 实施步骤

### Phase 1: Xcode 项目结构

**新增 Target**: `ArcBoxHelper`（Command Line Tool）

配置要点：
- Deployment Target: macOS 13.0
- Signing: Developer ID Application（与主 App 同 Team ID）
- Hardened Runtime: 开启
- Sandbox: **关闭**（daemon 需要操作系统路径）
- Entitlements: 无需特殊 entitlement（root 运行不需要）

**Build Phases（主 App target）**：
- 新增 Copy Files phase：将 `ArcBoxHelper` 复制到 `Contents/Library/HelperTools/`
- 新增 Run Script phase（**替代** Copy Files）：将 `io.arcbox.desktop.helper.plist` 中的
  `__DEVELOPMENT_TEAM__` 占位符替换为实际 build setting 值后输出到
  `Contents/Library/LaunchDaemons/`（Apple 不对 Copy Files 阶段的非 Info.plist 做变量展开）

**ArcBoxHelper target 额外配置**：
- 新增 `ArcBoxHelperInfo.plist` 作为 target 的 Info.plist（`INFOPLIST_FILE` build setting）
- 内含 `<key>ArcBoxTeamID</key><string>$(DEVELOPMENT_TEAM)</string>`，Xcode 构建时自动展开

---

### Phase 2: LaunchDaemon Plist

**源文件**: `LaunchDaemons/io.arcbox.desktop.helper.plist`（新增，模板文件）

Bundle ID 直接写死；`DEVELOPMENT_TEAM` 使用 `__DEVELOPMENT_TEAM__` 占位符，
由 Run Script phase 在构建时替换（Apple 仅对 target 自身的 Info.plist 做 `$(VAR)` 展开，
Copy Files phase 复制的其他 plist **不会被处理**）。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.arcbox.desktop.helper</string>

    <!-- Path relative to the .app bundle root -->
    <key>BundleProgram</key>
    <string>Contents/Library/HelperTools/ArcBoxHelper</string>

    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.arcbox.arcbox-desktop-swift</string>
    </array>

    <!-- XPC Mach service name; must match NSXPCListener in helper -->
    <key>MachServices</key>
    <dict>
        <key>io.arcbox.desktop.helper</key>
        <true/>
    </dict>

    <!--
        SpawnConstraint (macOS 13.3+, enforced on Sonoma+):
        Only the main ArcBox app (same Team ID + signing identifier) can trigger launch.
        Prevents arbitrary processes from invoking the root daemon.
        __DEVELOPMENT_TEAM__ is substituted by the Run Script build phase.
    -->
    <key>SpawnConstraint</key>
    <dict>
        <key>team-identifier</key>
        <string>__DEVELOPMENT_TEAM__</string>
        <key>signing-identifier</key>
        <string>com.arcbox.arcbox-desktop-swift</string>
    </dict>

    <!-- On-demand only: launchd starts this daemon when XPC requests arrive -->
    <!-- RunAtLoad intentionally omitted -->
</dict>
</plist>
```

**Run Script phase**（主 App target，放在 Copy Files for HelperTools **之后**）：

```bash
# Generate LaunchDaemon plist with DEVELOPMENT_TEAM substituted.
# Apple does NOT expand $(VAR) in non-Info.plist files copied via Copy Files phase.
INPUT="${SRCROOT}/LaunchDaemons/io.arcbox.desktop.helper.plist"
OUTPUT="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Library/LaunchDaemons/io.arcbox.desktop.helper.plist"

mkdir -p "$(dirname "$OUTPUT")"
sed "s/__DEVELOPMENT_TEAM__/${DEVELOPMENT_TEAM}/g" "$INPUT" > "$OUTPUT"
```

Input Files: `$(SRCROOT)/LaunchDaemons/io.arcbox.desktop.helper.plist`
Output Files: `$(BUILT_PRODUCTS_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/io.arcbox.desktop.helper.plist`

---

### Phase 3: XPC 协议定义

**文件**: `Packages/ArcBoxClient/Sources/ArcBoxClient/HelperProtocol.swift`（新增）

被 App 和 Helper 两侧共同引用。

```swift
// Protocol version. Bump when the API surface changes to prevent stale helpers
// from being called with incompatible arguments.
let kArcBoxHelperProtocolVersion = 1

@objc protocol ArcBoxHelperProtocol {

    // MARK: - Operation 1: /var/run/docker.sock

    /// Creates symlink: /var/run/docker.sock -> socketPath.
    ///
    /// Safety rules enforced by the helper:
    /// - socketPath must match /Users/<name>/.arcbox/*.sock (regex, not FileManager.home)
    /// - If /var/run/docker.sock already points to socketPath: no-op (idempotent)
    /// - If /var/run/docker.sock points to another ArcBox path: replace
    /// - If /var/run/docker.sock points to a non-ArcBox path (live OR dead): return error, do not replace
    /// - If /var/run/docker.sock is a regular file: return error, do not remove
    func setupDockerSocket(socketPath: String, reply: @escaping (NSError?) -> Void)

    /// Removes /var/run/docker.sock only if it points to an ArcBox socket path.
    /// No-op if the symlink points elsewhere (e.g., Docker Desktop).
    func teardownDockerSocket(reply: @escaping (NSError?) -> Void)

    // MARK: - Operation 2: CLI tools in /usr/local/bin

    /// Creates symlink: /usr/local/bin/abctl -> <appBundlePath>/Contents/MacOS/bin/abctl
    ///
    /// appBundlePath must be under /Applications/ (validated by helper).
    /// Only removes an existing link if it already points into an ArcBox bundle.
    func installCLITools(appBundlePath: String, reply: @escaping (NSError?) -> Void)

    /// Removes /usr/local/bin/abctl only if it points into an ArcBox.app bundle.
    func uninstallCLITools(reply: @escaping (NSError?) -> Void)

    // MARK: - Operation 3: /etc/resolver

    /// Writes /etc/resolver/<domain> with nameserver 127.0.0.1 at the given port.
    /// domain must be in the allowed list (validated by helper).
    func setupDNSResolver(domain: String, port: Int, reply: @escaping (NSError?) -> Void)

    /// Removes /etc/resolver/<domain>.
    func teardownDNSResolver(domain: String, reply: @escaping (NSError?) -> Void)

    // MARK: - Lifecycle

    /// Returns the helper protocol version for compatibility checking.
    func getVersion(reply: @escaping (Int) -> Void)
}
```

---

### Phase 4: Helper 实现

**文件**: `ArcBoxHelper/main.swift`（新增）

```swift
import Foundation
import ServiceManagement

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    /// Bundle ID of the main app. Hardcoded — matches PRODUCT_BUNDLE_IDENTIFIER in pbxproj.
    private static let appBundleID = "com.arcbox.arcbox-desktop-swift"

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // Validate caller using audit token (tamper-proof, unlike PID checks).
        // Team ID comes from the helper's own Info.plist (ArcBoxHelperInfo.plist),
        // where $(DEVELOPMENT_TEAM) is expanded by Xcode at build time.
        guard let teamID = Bundle.main.object(forInfoDictionaryKey: "ArcBoxTeamID") as? String,
              !teamID.isEmpty
        else { return false }

        do {
            try connection.setCodeSigningRequirement(
                "anchor apple generic and " +
                "certificate leaf[subject.OU] = \"\(teamID)\" and " +
                "identifier \"\(Self.appBundleID)\""
            )
        } catch {
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
        connection.exportedObject = HelperOperations()
        connection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "io.arcbox.desktop.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
```

**文件**: `ArcBoxHelper/HelperOperations.swift`（新增）

```swift
import Foundation

final class HelperOperations: NSObject, ArcBoxHelperProtocol {

    // MARK: - Operation 1: Docker Socket

    func setupDockerSocket(socketPath: String, reply: @escaping (NSError?) -> Void) {
        // Validate using regex — NOT FileManager.home, which returns /var/root when running as root.
        // Product constraint: ArcBox only supports GUI users whose home is under /Users/<name>/.
        guard isValidArcBoxSocketPath(socketPath) else {
            reply(makeError("Invalid socket path: \(socketPath)"))
            return
        }

        let symlinkPath = "/var/run/docker.sock"

        // Inspect the existing path with lstat (does not follow symlinks).
        var lstatBuf = Darwin.stat()
        if Darwin.lstat(symlinkPath, &lstatBuf) == 0 {
            // Something exists at this path.
            let isSymlink = (lstatBuf.st_mode & S_IFMT) == S_IFLNK

            guard isSymlink else {
                // A regular file or socket — not a symlink, do not remove.
                reply(makeError("/var/run/docker.sock is a regular file, not managed by ArcBox"))
                return
            }

            guard let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath) else {
                reply(makeError("Cannot read symlink target at \(symlinkPath)"))
                return
            }

            if existing == socketPath {
                // Already pointing to the correct target — idempotent.
                reply(nil); return
            }

            // Replacement policy: only replace when the existing symlink's TARGET
            // is itself an ArcBox path — regardless of whether that target is alive.
            // Any non-ArcBox symlink (live OR dead) is rejected to avoid stealing
            // sockets from Docker Desktop, OrbStack, or other runtimes.
            guard isValidArcBoxSocketPath(existing) else {
                reply(makeError("Socket owned by another runtime: \(existing)"))
                return
            }

            // Existing symlink points to a different ArcBox path — safe to replace.
            try? FileManager.default.removeItem(atPath: symlinkPath)
        }
        // Path did not exist, or was just removed — create the symlink.
        do {
            try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: socketPath)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func teardownDockerSocket(reply: @escaping (NSError?) -> Void) {
        let symlinkPath = "/var/run/docker.sock"
        if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath),
           isValidArcBoxSocketPath(existing) {
            try? FileManager.default.removeItem(atPath: symlinkPath)
        }
        // If symlink points elsewhere, leave it untouched.
        reply(nil)
    }

    // MARK: - Operation 2: CLI Tools

    func installCLITools(appBundlePath: String, reply: @escaping (NSError?) -> Void) {
        // appBundlePath must be a real app bundle under /Applications/.
        guard appBundlePath.hasPrefix("/Applications/"), appBundlePath.hasSuffix(".app") else {
            reply(makeError("appBundlePath must be under /Applications/ and end with .app"))
            return
        }

        // Actual binary path as per CLIRunner.swift:23.
        let tools: [(src: String, link: String)] = [
            ("\(appBundlePath)/Contents/MacOS/bin/abctl", "/usr/local/bin/abctl"),
        ]

        for t in tools {
            // Binary absent means the bundle is incomplete — return an error so the
            // App's startup path can decide whether to treat this as fatal or non-fatal.
            // Do NOT silently continue: a missing binary is a packaging problem, not an
            // "optional component not installed" scenario.
            guard FileManager.default.fileExists(atPath: t.src) else {
                reply(makeError("CLI binary not found in bundle: \(t.src)"))
                return
            }

            // Check what currently lives at the link path.
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: t.link) {
                if existing == t.src { continue }  // Already correct — idempotent.

                guard existing.contains("ArcBox.app") || existing.contains("/Applications/ArcBox") else {
                    // Link is owned by something else (e.g. Homebrew abctl).
                    // Return error so the App can surface this, not silently skip.
                    reply(makeError("/usr/local/bin/\(URL(fileURLWithPath: t.link).lastPathComponent) is owned by another tool: \(existing)"))
                    return
                }
                // Owned by a different ArcBox bundle (e.g. old install path) — replace.
                try? FileManager.default.removeItem(atPath: t.link)
            }

            do {
                try FileManager.default.createSymbolicLink(atPath: t.link, withDestinationPath: t.src)
            } catch {
                reply(error as NSError); return
            }
        }
        reply(nil)
    }

    func uninstallCLITools(reply: @escaping (NSError?) -> Void) {
        for link in ["/usr/local/bin/abctl"] {
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link),
               target.contains("ArcBox.app") || target.contains("/Applications/ArcBox") {
                try? FileManager.default.removeItem(atPath: link)
            }
        }
        reply(nil)
    }

    // MARK: - Operation 3: DNS Resolver

    func setupDNSResolver(domain: String, port: Int, reply: @escaping (NSError?) -> Void) {
        guard isAllowedDomain(domain), (1024...65535).contains(port) else {
            reply(makeError("Invalid domain or port"))
            return
        }
        let resolverPath = "/etc/resolver/\(domain)"
        let content = "nameserver 127.0.0.1\nport \(port)\n"
        do {
            try FileManager.default.createDirectory(
                atPath: "/etc/resolver", withIntermediateDirectories: true
            )
            try content.write(toFile: resolverPath, atomically: true, encoding: .utf8)
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func teardownDNSResolver(domain: String, reply: @escaping (NSError?) -> Void) {
        guard isAllowedDomain(domain) else {
            reply(makeError("Invalid domain")); return
        }
        try? FileManager.default.removeItem(atPath: "/etc/resolver/\(domain)")
        reply(nil)
    }

    func getVersion(reply: @escaping (Int) -> Void) {
        reply(kArcBoxHelperProtocolVersion)
    }

    // MARK: - Validation

    /// Validates that path matches /Users/<name>/.arcbox/<file>.sock.
    ///
    /// Must NOT use FileManager.homeDirectoryForCurrentUser: this helper runs as root,
    /// so that API returns /var/root — not the logged-in user's home directory.
    private func isValidArcBoxSocketPath(_ path: String) -> Bool {
        // Socket path is now ~/.arcbox/run/docker.sock (DaemonManager.swift:36).
        // Pattern allows one optional subdirectory under .arcbox/ (e.g. run/).
        let pattern = #"^/Users/[^/]+/\.arcbox/(?:[^/]+/)?[^/]+\.sock$"#
        return path.range(of: pattern, options: .regularExpression) != nil
    }

    private func isAllowedDomain(_ domain: String) -> Bool {
        ["arcbox.local", "arcbox.internal"].contains(domain)
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "io.arcbox.desktop.helper", code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
```

---

### Phase 5: App 侧 HelperManager

**文件**: `Packages/ArcBoxClient/Sources/ArcBoxClient/HelperManager.swift`（新增）

```swift
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

    /// Opens System Settings → General → Login Items for manual approval.
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
            var resumed = false
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
    private func withXPCConnection<T>(
        _ body: @escaping (ArcBoxHelperProtocol, @escaping (T) -> Void) -> Void,
        onFailure: @escaping () -> T
    ) async -> T {
        let conn = makeConnection()
        return await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
            var resumed = false
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

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: "io.arcbox.desktop.helper")
        conn.remoteObjectInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
        conn.resume()
        return conn
    }
}
```

---

### Phase 6: App 入口集成

**调用关系**：Helper 由 **App（GUI）** 直接通过 XPC 调用，与 CLI 和 arcbox daemon 无关。
- arcbox daemon → `SMAppService.agent()`（LaunchAgent，用户级，已有）
- ArcBoxHelper → `SMAppService.daemon()`（LaunchDaemon，root 级，新增）

**调用时机**：三个 helper 操作均在 daemon 启动**之前**顺序执行（各自 `try? await`，互不取消）。
`/var/run/docker.sock` 作为 dangling symlink 先行创建，待 daemon 启动后创建
`~/.arcbox/run/docker.sock`，symlink 自动生效，无需二次调用。

**文件**: `arcbox_desktop_swiftApp.swift`（修改）

```swift
@State private var helperManager = HelperManager()

.task {
    appDelegate.daemonManager = daemonManager
    appDelegate.eventMonitor = eventMonitor

    // 1. Seed boot-assets from bundle → ~/.arcbox/boot/
    await bootAssetManager.ensureAssets()

    // 2. Register privileged helper (SMAppService.daemon, root-level) and run
    //    all three privileged setup operations sequentially (each try? await,
    //    one failure does not cancel the others). Non-fatal: core works without helper.
    await setupHelper()

    // 3. Register CLI into PATH (user-level, complements /usr/local/bin symlink above).
    if let cli = try? CLIRunner() {
        try? await cli.run(arguments: ["setup", "install"])
    }

    // 4. Install Docker CLI tools and set arcbox as default context.
    await dockerToolSetupManager.installAndEnable()

    // 5. Start health monitoring.
    daemonManager.startMonitoring()

    // 6. Register daemon via SMAppService (LaunchAgent) and wait for reachability.
    //    Once the daemon creates ~/.arcbox/run/docker.sock, the /var/run/docker.sock
    //    symlink created in step 2 becomes active automatically.
    await daemonManager.enableDaemon()

    // 7. Initialize gRPC / Docker clients.
    initClientsIfNeeded()

    Task {
        try? await Task.sleep(for: .seconds(5))
        await bootAssetManager.checkForUpdates()
    }
}

private func setupHelper() async {
    do {
        try await helperManager.register()
    } catch HelperError.requiresApproval {
        // User previously denied in System Settings.
        // Show a non-blocking UI banner; core features still work.
        appVM.showHelperApprovalBanner = true
        return
    } catch {
        return
    }

    let socketPath = DaemonManager.dockerSocketPath   // ~/.arcbox/run/docker.sock
    let bundlePath = Bundle.main.bundleURL.path

    // Each operation is independent — await separately so that one failure
    // (e.g. socket occupied by OrbStack) does not cancel the other two.
    // `try? await (a, b, c)` would be fail-fast; three separate try? awaits are not.
    try? await helperManager.setupDockerSocket(socketPath: socketPath)
    try? await helperManager.installCLITools(appBundlePath: bundlePath)
    try? await helperManager.setupDNSResolver()
}
```

**完整初始化时序**：

```
App 启动
│
├─ 1. bootAssetManager.ensureAssets()           用户级，复制 boot 资产
│
├─ 2. helperManager.register()                  root 级，SMAppService.daemon 注册
│      ├─ setupDockerSocket()  ─┐
│      ├─ installCLITools()    ─┤  顺序执行，各自 try?，互不取消
│      └─ setupDNSResolver()  ─┘
│         /var/run/docker.sock 此时是 dangling symlink，不影响后续步骤
│
├─ 3. CLIRunner setup install                   用户级，写 shell PATH（~/.arcbox/bin）
│
├─ 4. dockerToolSetupManager.installAndEnable() 用户级，下载 Docker CLI + docker context
│
├─ 5. daemonManager.startMonitoring()           用户级，启动 3s 健康检查轮询
│
├─ 6. daemonManager.enableDaemon()              用户级，SMAppService.agent 注册
│      └─ daemon 创建 ~/.arcbox/run/docker.sock
│         → /var/run/docker.sock symlink 此时自动生效
│
└─ 7. initClientsIfNeeded()                     DockerClient + ArcBoxClient 就绪
```

---

### Phase 7: 卸载清理

**问题分析**：

| 场景 | 能否清理 |
|------|---------|
| App 内"Uninstall ArcBox"操作 | ✅ 可以，在 `applicationShouldTerminate` 中用 `.terminateLater` 等待异步清理 |
| 用户拖到废纸篓 | ❌ 无法触发清理（同 OrbStack、Docker Desktop 等所有 macOS 系统工具的共同限制） |

对于废纸篓删除，SMAppService daemon 注册会自动注销（launchd 不再启动 helper），
但 `/var/run/docker.sock`、`/usr/local/bin/abctl`、`/etc/resolver/arcbox.local` 会残留。
应在文档/Readme 中说明，并提供 `abctl uninstall` CLI 命令做手动清理。

**卸载流程**（通过 App 内"Uninstall ArcBox"菜单项触发）：

**文件**: `AppDelegate.swift`（修改）

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var daemonManager: DaemonManager?
    var helperManager: HelperManager?   // ← 新增
    var eventMonitor: DockerEventMonitor?
    var isUninstalling = false          // ← 新增，由 "Uninstall" 菜单动作设置

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        eventMonitor?.stop()
        guard let daemonManager else { return .terminateNow }

        Task { @MainActor in
            daemonManager.stopMonitoring()

            if isUninstalling, let helperManager {
                // Teardown must complete before daemon is stopped, so that
                // each helper operation can confirm the current state.
                try? await helperManager.teardownDockerSocket()
                try? await helperManager.uninstallCLITools()
                try? await helperManager.teardownDNSResolver()
                try? SMAppService.daemon(
                    plistName: "io.arcbox.desktop.helper.plist"
                ).unregister()
            }

            await daemonManager.disableDaemon()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

**菜单动作**（`ContentView.swift` 或 Settings 视图中新增）：

```swift
Button("Uninstall ArcBox...") {
    let alert = NSAlert()
    alert.messageText = "Uninstall ArcBox?"
    alert.informativeText = "This will remove CLI tools, DNS resolver config, and the Docker socket symlink."
    alert.addButton(withTitle: "Uninstall")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
        appDelegate.isUninstalling = true
        NSApp.terminate(nil)
    }
}
```

---

## 文件变更清单

| 文件 | 动作 |
|------|------|
| `ArcBoxHelper/main.swift` | **新增** — daemon 入口，XPC listener，调用方 code signing 验证 |
| `ArcBoxHelper/HelperOperations.swift` | **新增** — 3 个特权操作实现，含 lstat 安全检查和 regex 路径校验 |
| `ArcBoxHelper/ArcBoxHelper.entitlements` | **新增** — 空 entitlements（root daemon 无需特殊 entitlement） |
| `ArcBoxHelper/ArcBoxHelperInfo.plist` | **新增** — Helper target 的 Info.plist，含 `ArcBoxTeamID = $(DEVELOPMENT_TEAM)`（Xcode 展开） |
| `LaunchDaemons/io.arcbox.desktop.helper.plist` | **新增** — launchd 配置模板，`__DEVELOPMENT_TEAM__` 占位符由 Run Script 替换 |
| `Packages/ArcBoxClient/Sources/ArcBoxClient/HelperProtocol.swift` | **新增** — XPC 协议定义（App 和 Helper 共享） |
| `Packages/ArcBoxClient/Sources/ArcBoxClient/HelperManager.swift` | **新增** — App 侧 SMAppService 注册 + XPC 调用封装（连接生命周期正确管理） |
| `arcbox_desktop_swiftApp.swift` | **修改** — 初始化 helperManager，`setupHelper()` 函数 |
| `AppDelegate.swift` | **修改** — 持有 helperManager，`isUninstalling` 标志，卸载清理逻辑 |
| `AppViewModel.swift` | **修改** — 新增 `showHelperApprovalBanner: Bool` 属性 |

---

## 安全威胁模型

```
威胁                                 防御层
──────────────────────────────────────────────────────────────────────
任意进程调用 root daemon              plist SpawnConstraint（launchd 层）
                                      + setCodeSigningRequirement（XPC 运行时层，audit token）
路径遍历（写入任意系统路径）            isValidArcBoxSocketPath：regex 而非 FileManager.home，
                                      确保 root 环境下校验仍然正确
覆盖第三方 Docker 运行时 socket        setupDockerSocket：lstat 检测，非 ArcBox symlink
                                      （无论 live/dead）一律拒绝替换
写入任意二进制到系统目录               只创建软链接，source 必须在 .app bundle 内
DNS 劫持（写入任意 resolver）          isAllowedDomain 硬编码白名单
旧版 App 调用新 helper                 getVersion() + versionMismatch 检查
XPC 连接释放导致 reply 卡死            call() 持有 conn 直到 reply 返回后再 invalidate()
Helper 二进制被替换                    Gatekeeper 校验整个 .app bundle 签名
卸载后特权进程残留                     SMAppService daemon 随 .app 删除自动注销
```

---

## 验证方式

| 场景 | 验证点 |
|------|--------|
| 首次安装 | 弹出一次性系统授权对话框，批准后不再弹出 |
| `/var/run/docker.sock` | `ls -la /var/run/docker.sock` → 指向 `~/.arcbox/run/docker.sock` |
| CLI 工具 | `which abctl` → `/usr/local/bin/abctl`；`abctl --version` 正常 |
| DNS Resolver | `cat /etc/resolver/arcbox.local` → 含 `nameserver 127.0.0.1\nport 5553` |
| 幂等性 | 多次启动 App 不报错，不产生重复 symlink |
| 第三方 socket 保护 | OrbStack 运行时，`setupDockerSocket` 返回 error，OrbStack socket 不变 |
| 用户拒绝授权 | App 显示引导 banner，core 功能（Docker context）仍正常 |
| 非 ArcBox 进程尝试调用 | XPC 连接被拒，helper 不响应 |
| socket 被 OrbStack 占用时启动 | `setupDockerSocket` 返回 error，`installCLITools` 和 `setupDNSResolver` **仍正常执行**（非 fail-fast） |
| `/usr/local/bin/abctl` 被第三方占用 | `installCLITools` 返回明确 error（含占用者路径），App 可 surface 提示 |
| App 内 Uninstall | symlink / resolver / CLI link 均被清理，daemon 注销 |
| 拖到废纸篓 | daemon 注销，但 3 个 system-level 条目残留（已知限制，`abctl uninstall` 在删除 .app **之前**可手动清理） |
