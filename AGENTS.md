# ArcBox Desktop — Agent Guidelines

## Build & Test
- Build: `xcodebuild build -project ArcBox.xcodeproj -scheme ArcBox -configuration Debug`
- Test all: `xcodebuild test -project ArcBox.xcodeproj -scheme ArcBox -configuration Debug -destination 'platform=macOS'`
- Swift-only (skip Rust): add `SKIP_RUST_BUILD=1 CODE_SIGN_IDENTITY=-` to xcodebuild
- Rust binaries: the Xcode build phase runs `scripts/embed-arcbox-binaries.py`, which calls `make build-rust` in `../arcbox`

## Architecture
- **ArcBox/** — SwiftUI macOS app (MVVM): Views/, ViewModels/, Models/, Services/, Components/, Theme/
- **Packages/ArcBoxClient** — gRPC client (protobuf), DaemonManager (SMAppService), StartupOrchestrator
- **Packages/DockerClient** — Docker Engine API client over Unix socket (`~/.arcbox/run/docker.sock`)
- **Packages/K8sClient** — Kubernetes API client with kubeconfig + exec-based auth
- Daemon (`arcbox-daemon`) is a separate Rust binary from the `../arcbox` repo; communicates via gRPC over `~/.arcbox/run/arcbox.sock`
- Entitlements for the daemon live in `../arcbox/bundle/arcbox.entitlements` (single source of truth)

## Daemon Signing
- The daemon MUST be signed with Developer ID, not Xcode's Apple Development certificate
- Restricted entitlements (`com.apple.security.virtualization`, `com.apple.security.hypervisor`, `com.apple.vm.networking`) require Developer ID for AMFI to accept them; Apple Development signing causes silent `OS_REASON_EXEC` crash loops from launchd
- `embed-arcbox-binaries.py` resolves Developer ID by SHA-1 hash (not name, to avoid keychain ambiguity) independently of Xcode's `CODE_SIGN_IDENTITY`
- If daemon fails to start locally: `make -C ../arcbox sign-daemon`

## SwiftUI Startup Timing — Known Pitfalls

### `.task(id:)` race with `onChange`
Multiple daemon state properties are set in a single `applySetupStatusSync()` call (e.g. `state = .running` and `setupPhase = .ready` simultaneously). When a `.task(id:)` depends on one property and an `onChange` of another property creates a dependency (like `DockerClient`), the task may fire before `onChange` runs, receiving stale values.

**Rule**: if a `.task(id:)` needs both a daemon state AND an object created in `onChange`, combine both into the task id: `.task(id: condition1 && condition2)`.

### Boolean `hasCompleted` flags vs explicit state enums
A bare `Bool` like `hasCompletedInitialLoad` cannot distinguish "never started" from "in progress" from "succeeded" from "failed". This causes:
- Empty state flash: setting `true` before data arrives shows the empty view
- No retry UX: no way to represent a failed state
- Misleading loading indicators: can't show different messages for different phases

**Rule**: use an enum (`waiting → loading → loaded | failed`) for any multi-phase async operation visible in the UI.

### `dockerSocketLinked` vs Docker API readiness
`daemonManager.dockerSocketLinked` tracks the CLI convenience symlink (`/var/run/docker.sock`), NOT the Docker API socket (`~/.arcbox/run/docker.sock`). Use `setupPhase.isDockerReady` (`.ready` or `.degraded`) to gate Docker API calls.

### Default tab vs lazy tabs
The default tab's view renders during startup. Other tabs render lazily when the user switches to them. This means timing bugs in `.task(id:)` only manifest on the default tab — other tabs work by accident because dependencies are already available when they appear. Always test startup behavior on the default tab specifically.

## Code Style
- Swift 6 strict concurrency (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`)
- ViewModels use `@Observable`; environment injection via custom `EnvironmentKey`
- Logging: use the `Log` enum (OSLog-based) in the app, `ClientLog` in Packages
- Prefer `async/await` over Combine; use `Task.detached` only for Sendable-isolated gRPC calls
- No Combine, no third-party UI libraries; only external deps: Sparkle, SwiftTerm, Sentry
- Imports: Foundation/SwiftUI first, then local packages, then third-party; one blank line before body
