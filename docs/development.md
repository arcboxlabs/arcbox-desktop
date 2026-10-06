# Development

## Setup

```bash
git clone https://github.com/arcboxlabs/arcbox-desktop.git
cd arcbox-desktop

cp Local.xcconfig.example Local.xcconfig   # set DEVELOPMENT_TEAM
make build
```

`DEVELOPMENT_TEAM` is the only value you have to fill in. The Sentry, PostHog, and OIDC placeholders can
stay as they are — each one is checked for its placeholder at startup, so telemetry and platform sign-in
simply stay off.

| Command | What it does |
|---|---|
| `make build` | Debug, Swift only, no embedded Rust binaries |
| `make build-runnable` | complete signed Debug app using the isolated development profile |
| `make test` | full test suite |
| `make audit-accessibility` | Xcode's accessibility audit over the signed `ArcBox Dev` app; needs the same setup as `make build-runnable` |
| `make format` / `make lint` | swift-format and SwiftLint |
| `make generate-xcodeproj` | run after adding or removing a file |
| `make lint-xtask` / `make test-xtask` | the Rust packaging crate, gated separately |
| `make dmg` / `make dmg-signed` | package the app — see below, the two are not interchangeable |

> **Do not run `xcodebuild` or `xcodegen` directly.** This repo uses devenv, whose Rust toolchain exports
> a nix `CC`/`SDKROOT`/`DEVELOPER_DIR`; a bare `xcodebuild` then fails with `no such module 'SwiftShims'`.
> The Makefile targets run in an allowlisted environment and behave identically inside `devenv shell`, on
> a clean machine, and in CI.

## Running against a real daemon

Swift-only keeps the loop fast. For a Debug build that can boot machines and use Docker normally, run:

```bash
./script/build_and_run.sh
```

This builds and signs the daemon, then stages boot assets, guest runtime, agents, Docker tools, and
completions into the Debug bundle. It uses the `development` profile (`~/.arcbox-dev`) so it does not
share daemon state with an installed production app. The machine must have the ArcBox Developer ID
certificate because macOS rejects the daemon's virtualization entitlements under ad-hoc signing.
The script creates an isolated `.build/arcbox-<version>` worktree so every runtime binary matches
[`arcbox.version`](../arcbox.version), without changing the neighboring ArcBox checkout. It rejects
the wrong commit and any tracked or untracked, non-ignored source changes in that worktree.
Use `./script/build_and_run.sh --verify` to skip onboarding for that launch and wait for the
development LaunchAgent, socket, and bundled `abctl` connection. The launch override does not
change the stored onboarding preference.

To get the same behavior from Xcode's Run button, enable the full-debug settings documented at the
bottom of `Local.xcconfig.example`. Codex exposes the same script as its project Run action.

Packaging also supplies a daemon for distribution testing.
Both DMG targets first run `make prefetch`, which builds `arcbox-daemon`, `abctl`, and `arcbox-helper` from
`../arcbox` (override with `ARCBOX_DIR`) and downloads the guest boot assets. They differ in how the
daemon ends up signed, and that difference decides whether the app can do anything:

| Target | Daemon signature | Good for |
|---|---|---|
| `make dmg` | ad-hoc, no entitlements | packaging changes — the app launches, the daemon does not |
| `make dmg-signed` | Developer ID + entitlements | actually running the app |

The daemon's restricted entitlements (`com.apple.security.virtualization`,
`com.apple.security.hypervisor`, `com.apple.vm.networking`) are only honored under Developer ID; without
them launchd kills it in a silent `OS_REASON_EXEC` loop. `make dmg` passes no identity to the packager,
which then deep-signs the daemon bundle ad-hoc and drops the entitlements — including the Developer ID
signature `prefetch` had just applied to the bare binary. `make dmg-signed` re-signs with your keychain
identity and verifies the entitlements survived; it refuses to run when no identity is found. If a daemon
that should be signed still won't start, re-sign it with `make -C ../arcbox sign-daemon`.

The guest agents are best-effort. `build-rust` ignores a failing `build-agent`, and packaging only prints
a warning when `arcbox-agent` or `vm-agent` is missing from
`../arcbox/target/aarch64-unknown-linux-musl/release/`. A DMG can therefore build cleanly and still be
unable to boot a guest — scan the packaging output for those warnings.

## Bumping the embedded daemon

```bash
make bump-arcbox VERSION=v0.5.6
```

This updates [`arcbox.version`](../arcbox.version) and regenerates the gRPC client atomically, restoring
both if generation fails. CI enforces that they stay in sync with `make verify-arcbox-protobuf`.

You rarely have to run it yourself: every arcbox release dispatches the
[Bump ArcBox](../.github/workflows/bump-arcbox.yml) workflow, which runs the same target on a macOS
runner and opens the PR. Dispatch it from the Actions tab to pin any other tag.

The gRPC generator applies the checked-in keyword patch to an owned copy of grpc-swift-protobuf 1.3.1 at revision `53e89e3a5d417307f70a721c7b83e564fefb1e1c`. The patch escapes Swift method keywords and preserves RPC wire names. The generator uses the committed resolved versions and leaves SwiftPM's managed checkout unchanged. Review the patch before changing the generator revision.

## Project layout

```
ArcBox/                    SwiftUI app
├── Views/                 one directory per source: Containers, Images, Machines, Sandboxes, ...
├── ViewModels/            @Observable state
├── Models/                data models
├── Services/              Docker / machine / sandbox event monitors, diagnostics export
├── Integrations/          Docker CLI + context, terminal apps, guest filesystem
├── Components/            reusable UI
└── Theme/                 design tokens

Packages/
├── ArcBoxClient/          gRPC client, DaemonManager (SMAppService), StartupOrchestrator
├── DockerClient/          Docker Engine API over a Unix socket (OpenAPI generated)
├── K8sClient/             Kubernetes API with kubeconfig and exec-based auth
└── ArcBoxAuth/            OAuth/PKCE session and keychain storage

LaunchDaemons/             launchd plist for the daemon
xtask/                     embedding, signing, and packaging (Rust)
```

## Tech stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI + `@Observable`, Swift 6 strict concurrency |
| Daemon | gRPC (grpc-swift + protobuf) |
| Docker | OpenAPI-generated client |
| Terminal | SwiftTerm |
| Daemon lifecycle | SMAppService |
| Auto-updates | Sparkle |
| Crash reports and analytics | Sentry, PostHog |

No Combine, no third-party UI frameworks.

## Further reading

[AGENTS.md](../AGENTS.md) carries the rest: code style, and the SwiftUI startup pitfalls we keep
re-learning — `.task(id:)` racing `onChange`, `Bool` flags that should be state enums, and why timing bugs
only show up on the default tab.

## Generating from a local runtime checkout

Generate a client from an explicit local runtime checkout with `make generate-arcbox-protobuf ARCBOX_DIR=/path/to/arcbox`. The command does not change `arcbox.version`. Local generation is for coordinated runtime development; release generation and `make verify-arcbox-protobuf` still use the pinned runtime version. Before release, publish the compatible runtime and run `make bump-arcbox VERSION=vX.Y.Z` to update the pin and generated sources together.

## Developing runtime storage changes

Storage health is independent of daemon connection and Docker API readiness. Missing or unrecognized fields mean unknown health. `MOUNTED_READ_WRITE` describes a mount observation; the state does not certify durable writes. The Desktop retains a stale observation after a disconnect and does not treat an unknown observation as recovery. Notifications reset only after a current healthy observation for the affected volume.

Storage recovery runs in the daemon after the initiating stream disconnects. `SetupStatus.storage_recovery` replays the operation ID, progress, terminal outcome, and `storage_protected`. Desktop recognizes completion only from `COMPLETE` for the same operation. Completion does not release write protection: check-only completion and failed recovery retain protection, including after reconnecting. Desktop uses the typed protection field to block writes until recovery verifies writes and releases protection. Desktop does not start another operation while completion is unknown, and quit leaves the daemon running in that state. During quit, recovery observation remains active so a terminal status replay can cancel a pending recovery stream and finish the recovery wait.

`RuntimeStorageRecoveryIntegrationTests` uses the real recovery model and `WatchSetupStatus` against an explicit disposable runtime. The test stops and restarts the runtime's VM and writes to its data disks. Supply a runtime with isolated data, sockets, and network configuration. Run the test with `ARCBOX_LIVE_RECOVERY_ACTION=check`, stop the daemon, and restart the daemon with the same data directory. Run the test again with `ARCBOX_LIVE_RECOVERY_ACTION=recover` and `ARCBOX_LIVE_RECOVERY_EXPECTED_OPERATION` set to the completed check-only operation ID. The second run verifies replay before starting recovery.

Pass `TEST_RUNNER_ARCBOX_LIVE_RECOVERY_SOCKET`, `TEST_RUNNER_ARCBOX_LIVE_RECOVERY_ACTION`, and the optional `TEST_RUNNER_ARCBOX_LIVE_RECOVERY_EXPECTED_OPERATION` through the Makefile's `XCODE_ENV` override. Select the test with `make test XCODEBUILD_EXTRA='-only-testing:ArcBoxTests/RuntimeStorageRecoveryIntegrationTests'`. Xcode removes the `TEST_RUNNER_` prefix. Without the socket variable, the test skips without connecting to a runtime.
