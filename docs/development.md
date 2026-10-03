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
