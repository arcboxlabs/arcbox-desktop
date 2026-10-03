# ArcBox Desktop — Agent Guidelines

## Build & Test
- Build: `make build` — Swift only, no embedded Rust binaries
- Test all: `make test`
- **A local package's tests only run because `ArcBoxTests` compiles their sources.** xcodegen refuses a SwiftPM test target in the scheme's test action ("invalid test target"), so a package's `Tests/` directory is listed under `ArcBoxTests.sources` in `project.yml`. Add a new local package's test path there or nothing will ever run it — `swift test` in the package directory is not part of any gate. The bundle links them through its test host; adding the package as a direct dependency instead duplicates the link and fails.
- **The test host never boots the app.** `AppDelegate` skips Sentry, PostHog and the `ApplicationCoordinator` when XCTest is loaded (`AppDelegate.isTestHost`). A host that booted installed the helper, opened Fleet connections and read the sign-in item from the login keychain; `make test` signs the host ad hoc, whose designated requirement changes every build, so that read prompted for the keychain password on every run and "Always Allow" could never stick. A test that needs the coordinator builds one itself. The development profile also keeps its own sign-in item (`com.arcboxlabs.desktop.dev.oidc`), so a dev build never touches the shipped app's session.
- Format / lint: `make format`, `make lint`
- xtask (Rust): `make lint-xtask`, `make test-xtask` — `make lint`/`make test` cover Swift only
- Regenerate the Xcode project after adding or removing a file: `make generate-xcodeproj`
- Rust binaries: the Xcode build phase runs `cargo xtask macos embed`, which calls `make build-rust` in `../arcbox`. `make build`/`make test` set `SKIP_RUST_BUILD=1`. Use `make dmg-signed` for a bundle that actually runs — `make dmg` ad-hoc signs the daemon bundle without entitlements, so its daemon is killed on launch.

**Do not call `xcodebuild` or `xcodegen` directly.** This repo uses devenv, whose Rust toolchain exports `CC`/`CXX`/`LD`/`SDKROOT`/`DEVELOPER_DIR` (pointed at a nix SDK) and ~30 `NIX_*` variables. A bare `xcodebuild` then fails with `no such module 'SwiftShims'`, `unknown argument: -index-store-path`, or `ld: unknown options: -Xlinker`, and devenv's `xcodegen` is older than `project.yml`'s `minimumXcodeGenVersion`. The Makefile targets run xcodebuild in an allowlisted environment and pick a new enough xcodegen, so they work identically inside `devenv shell` and on a clean CI runner — which is what CI itself runs.

## Architecture
- **ArcBox/** — SwiftUI macOS app (MVVM): App/, Views/, ViewModels/, Models/, Services/, Components/, Theme/, Integrations/, Support/
- **Packages/ArcBoxClient** — gRPC client (protobuf), DaemonManager (SMAppService), StartupOrchestrator
- **Packages/DockerClient** — Docker Engine API client over Unix socket (`~/.arcbox/run/docker.sock`)
- **Packages/K8sClient** — Kubernetes API client with kubeconfig + exec-based auth
- **Packages/ArcBoxAuth** — OIDC/PKCE sign-in for ArcBox Platform, tokens in the keychain
- Daemon (`arcbox-daemon`) is a separate Rust binary from the `../arcbox` repo; communicates via gRPC over `~/.arcbox/run/arcbox.sock`
- Entitlements for the daemon live in `../arcbox/bundle/arcbox.entitlements` (single source of truth)
- When bumping the embedded daemon version, use `make bump-arcbox VERSION=vX.Y.Z` so `arcbox.version` and generated protobuf client code are updated atomically

## Daemon Signing
- The daemon MUST be signed with Developer ID, not Xcode's Apple Development certificate
- Restricted entitlements (`com.apple.security.virtualization`, `com.apple.security.hypervisor`, `com.apple.vm.networking`) require Developer ID for AMFI to accept them; Apple Development signing causes silent `OS_REASON_EXEC` crash loops from launchd
- `cargo xtask macos embed` resolves Developer ID by SHA-1 hash (not name, to avoid keychain ambiguity) independently of Xcode's `CODE_SIGN_IDENTITY`
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

### `fixedSize(horizontal: false, vertical: true)` window blowup (macOS 26)
Any state change inside a `fixedSize(vertical: true)` subtree in a main-window view triggers a window-sizing pass that resizes the window — or, if the window can't grow, the `NavigationSplitView` content inside it — to the screen's *visible-frame height* (content slides under the title bar, bottom-pinned views disappear). Verified on macOS 26.5 with a minimal repro: inserting, removing, or even changing the text of such a label fires it; the same label without `fixedSize` does not, and still wraps correctly inside width-constrained containers.

**Rule**: don't use `fixedSize(vertical: true)` on labels whose content appears/changes dynamically in the main window (error banners, status text). Text wraps without it in width-bounded layouts; use it only for genuinely static text, ideally in sheets.

## Code Style
- Swift 6 strict concurrency (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`)
- ViewModels use `@Observable`; environment injection via custom `EnvironmentKey`
- Logging: use the `Log` enum (OSLog-based) in the app, `ClientLog` in Packages
- Crash reporting: only the app links Sentry. Packages emit through `ClientDiagnostics` and the app installs the sink — a package that imports Sentry drags its ~500 MB of binary artifacts into protobuf regeneration
- Prefer `async/await` over Combine; use `Task.detached` only for Sendable-isolated gRPC calls
- No Combine, no third-party UI libraries; only external deps: Sparkle, SwiftTerm, Sentry, PostHog
- Imports: one alphabetically sorted block, with `@testable` imports in a separate block below it; one blank line before the body. This is enforced by swift-format's `OrderedImports`, so `make format` is authoritative — do not hand-order imports
