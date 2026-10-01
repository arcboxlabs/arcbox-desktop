# ArcBox Desktop — Agent Guidelines

## Build & Test
- Build: `make build` — Swift only, no embedded Rust binaries
- Test all: `make test`
- **A local package's tests only run because `ArcBoxTests` compiles their sources.** xcodegen refuses a SwiftPM test target in the scheme's test action ("invalid test target"), so a package's `Tests/` directory is listed under `ArcBoxTests.sources` in `project.yml`. Add a new local package's test path there or nothing will ever run it — `swift test` in the package directory is not part of any gate. The bundle links them through its test host; adding the package as a direct dependency instead duplicates the link and fails.
- **The test host never boots the app.** `AppDelegate` skips Sentry, PostHog and the `ApplicationCoordinator` when XCTest is loaded (`AppDelegate.isTestHost`). A host that booted installed the helper, opened Fleet connections and read the sign-in item from the login keychain; `make test` signs the host ad hoc, whose designated requirement changes every build, so that read prompted for the keychain password on every run and "Always Allow" could never stick. A test that needs the coordinator builds one itself. The development profile also keeps its own sign-in item (`com.arcboxlabs.desktop.dev.oidc`), so a dev build never touches the shipped app's session.
- Run one test class: `make test XCODEBUILD_EXTRA='-only-testing:ArcBoxTests/<ClassName>'`. `XCODEBUILD_EXTRA` is spliced into the xcodebuild flags.
- `make test` scrubs the environment (`env -i`), so a `TEST_RUNNER_*` variable reaches the test host only through an `XCODE_ENV="/usr/bin/env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin TEST_RUNNER_FOO=1"` override on the make command line.
- A `DockerClient` created in a test must be shut down (`try await docker.shutdown()`) before the test returns. AsyncHTTPClient traps in `deinit` otherwise and takes the whole test host down.
- CI's `macos-26` runners are 3–5× slower and noisier than a developer Mac. Never assert an absolute wall-clock budget below 3× the local Debug median; prefer counts (body evaluations, row operations) and flatness ratios. Two PRs were blocked by 1 s caps that pass locally in 0.3 s.
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
- **Packages/ProcessSupport** — child-process primitives (`Process.armExit()`, `waitForExit`, `runCapturingStandardOutput`); the only place a `Process` is awaited
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
- `@Observable` skips the notification when an `Equatable` property is assigned an equal value. `ContainerViewModel ==` deliberately ignores ports and stats, so a `containers` write that changes only those fields is invisible to observers; put anything the list must react to into that `==`.
- No Combine, no third-party UI libraries; only external deps: Sparkle, SwiftTerm, Sentry, PostHog
- Imports: one alphabetically sorted block, with `@testable` imports in a separate block below it; one blank line before the body. This is enforced by swift-format's `OrderedImports`, so `make format` is authoritative — do not hand-order imports

## Testing UI Off-Screen
- `OffscreenHost` (ArcBoxTests) lays out a SwiftUI root in a never-shown `NSWindow`. With `NSHostingController.sceneBridgingOptions = .all` the `.toolbar` and the AppKit-backed platform views materialize without ordering the window on screen. `SegmentedControlRelayoutTests` is the reference.
- Live `NSTableView`/`NSOutlineView` row views exist only in a window that is ordered in with a non-zero content size. Park a borderless window off-screen (origin -20000,-20000), call `setContentSize` *after* assigning `contentViewController` (the assignment shrinks the window to the view's zero frame), then `window.display()`. Set `isReleasedWhenClosed = false` on every test window; closing a self-releasing window under ARC double-releases it and crashes at autorelease-pool drain. `ContainersListIncrementalUpdateTests` is the reference.
- SwiftUI builds its accessibility nodes only while an assistive client is attached; a headless CI runner never has one, so a test that reads the SwiftUI AX tree must `XCTSkip` when the hosted root reports no accessibility children. Those nodes do not cast to `NSAccessibilityProtocol`; read them through dynamic messaging (`value(forKey: "accessibilityChildren")`, `"accessibilityRole"`, `"accessibilitySelected"`).
- Render a SwiftUI view to PNG with `cacheDisplay(in:to:)` into an `NSBitmapImageRep` you size yourself (2× = `pixelsWide` 2 × bounds), under the wanted `NSAppearance`. `ImageRenderer` skips `Gauge` and resolves vibrant colors on its own terms; `cacheDisplay` renders Liquid Glass (`glassEffect`) as its raw normal map, so render the subtree under the glass, not the glass. `ActivityMetricStripSnapshotTests` is the reference.
- A per-update cost benchmark drives the real `@Observable` mutation, then `needsLayout = true; layoutSubtreeIfNeeded(); displayIfNeeded(); CATransaction.flush()`. An off-screen borderless window is enough: the CA commit and text rasterization run and show up in `sample`. `ActivityTickBenchmarkTests` is the reference.
- Count body evaluations with `recordingBodyEvaluation(of:)` + `BodyEvaluationCounter` (DEBUG-only, `ArcBox/Support`). "0 evaluations of the view that holds the control across N hot updates" is the regression guard for the pitfalls below; a wall-clock number is not.

## Main-Thread Performance — Known Pitfalls
Each rule below closed a Sentry App Hang (≥2 s main thread) cluster in 1.37.0. The reference fix is named so the pattern can be copied.

### A segmented picker never shares a body with hot state
`Picker(...).pickerStyle(.segmented)` is SwiftUI's `SystemSegmentedControl`: an `NSSegmentedControl` hosting its own inner view graph, re-evaluated on every `sizeThatFits` (~1.3–2 ms per layout pass). When the body that contains it also observes a hot stream (log batches, list refreshes, stats), every invalidation re-measures the control — the whole main-thread stack of ARCBOX-DESKTOP-SWIFT-T/-30/-32/-2R/-4V. Put the picker in a leaf `View` that reads only its own bindings and the hot content in a sibling leaf (`ContainerLogsToolbar` / `ContainerLogsContent`, `SandboxPortsToolbar` / `SandboxPortsContent`), and pin the split with `BodyEvaluationCounter`. `DetailTabPicker`'s `accessibilityRepresentation { Picker(.segmented) }` creates no platform view on macOS 26 (accessibility nodes only) and is exempt.

### An outline view is diffed, never reloaded, on an item change
`NSOutlineView.reloadData()` plus re-expanding every group rebuilds every visible row synchronously; with a few dozen containers that is a 2 s hang on every Docker event (ARCBOX-DESKTOP-SWIFT-52/-4D/-B7). `ContainerListTree` is the reference: nodes keep their identity for life, a change is applied as removals → minimal moves → in-place `configure` → insertions inside `beginUpdates`/`endUpdates`, and `reloadData()` is reserved for an empty tree. Cells hide their action views *before* `NSStackView.setViews` (hiding after adding fires one `setVisibilityPriority` KVO pass per view) and hoist every `NSImage(systemSymbolName:)` into a `static let`.

### A SwiftUI wrapper's `body` must not read what the AppKit controller observes
`ContainersListView.body` read `runningCount`, `loadState` and `isSearching`, so every `containers` write rebuilt the `ToolbarItemGroup` and re-ran `updateNSViewController` (ARCBOX-DESKTOP-SWIFT-43, 95 events). Hot reads live in their own `ViewModifier`s with their own tracking (`ContainersListSubtitle`, `ContainersListSearch`); the wrapper body depends on daemon state only.

### Swift Charts is not a live sparkline
A `Chart` re-resolves every mark on every update (~1.5 ms per 60-point sparkline per tick, and `_Charts_*` frames are the whole stack of ARCBOX-DESKTOP-SWIFT-3G). `Sparkline` draws with `Canvas` through `SparklineGeometry` (monotone cubic, pure and unit-tested). Charts' automatic x domain also includes zero, so a sequence-number x axis compressed the live figure toward the right as the session aged. A SwiftUI `Table` costs ~0.3 ms per changed row plus a row-height pass, and re-sorting a row is a remove + insert: sort on the precision the column displays with a total tie-break (`ActivityRowGrouping.precedes`), and compute the grouped rows once per body. Do not put `.contentTransition(.numericText())` on a value that changes every second; the digit roll costs ~160–200 ms of main-thread CPU per tick.

## Child Processes
- Never wait for a child with `Process.waitUntilExit()` from Swift concurrency, `Task.detached` included. It services the calling thread's run loop, and on a cooperative-pool thread the termination wake-up can fail to arrive: the waiter stays parked in `-[NSConcreteTask waitUntilExit] → mach_msg2_trap` after the child is gone (reproduced 2026-10-01 with six concurrent children terminated at 300 ms; wedged in round 3 every time). Use `Process.armExit()` + `waitForExit` or `runCapturingStandardOutput(_:timeout:outputLimit:)` from `Packages/ProcessSupport`; they arm `terminationHandler` before `run()`.
- Never spawn a child on the main actor and poll it (`Thread.sleep`, `isRunning` loops). `binaryVersion` and `KubeConfig.runExecPlugin` did and blocked startup for the length of a Gatekeeper scan or an exec plugin; both are `nonisolated async` now. `KubeConfig(yaml:)` only parses; `KubeConfig.load(yaml:)` resolves exec credentials.
- The child's exit bounds the call, not EOF: a grandchild that inherited stdout keeps the pipe open after the child exits. Read the pipe alongside the wait with an output limit, drain for `processOutputDrainGrace` after the exit, then close the read end. Cancellation sends SIGTERM, then SIGKILL after `processTerminationGrace`, and still reaps the child. Error precedence is `CancellationError` > `ProcessOutputLimitExceeded` > `ProcessTimedOut`: a cancelled startup must propagate cancellation, not read as a failed probe.
- A test that needs a child to outlive a timeout runs `#!/bin/bash` + `exec -a "$0" /bin/sleep 30`: `exec -a` keeps the script path (the `pgrep -f` marker) as argv[0], and no forked `sleep` holds the stdout pipe. Wait for the fake's own program with `pgrep -f '^<path>'` (bash's cmdline has the path second), not for the shell; a cold bash takes ~350 ms to reach `trap`. Open a release FIFO with `O_WRONLY | O_NONBLOCK` so a dead reader fails the test instead of hanging it. `XCTAssert*` autoclosures cannot `await`; bind the awaited value to a local first.
