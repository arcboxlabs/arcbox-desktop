# ArcBox Desktop — Agent Guidelines

## Build & Test
- Build: `xcodebuild build -project ArcBox.xcodeproj -scheme ArcBox -configuration Debug`
- Test all: `xcodebuild test -project ArcBox.xcodeproj -scheme ArcBox -configuration Debug -destination 'platform=macOS'`
- Swift-only (skip Rust): add `SKIP_RUST_BUILD=1 CODE_SIGN_IDENTITY=-` to xcodebuild
- Rust binaries: the Xcode build phase runs `scripts/embed-arcbox-binaries.sh`, which calls `make build-rust` in `../arcbox`

## Architecture
- **ArcBox/** — SwiftUI macOS app (MVVM): Views/, ViewModels/, Models/, Services/, Components/, Theme/
- **Packages/ArcBoxClient** — gRPC client (protobuf), DaemonManager (SMAppService), StartupOrchestrator
- **Packages/DockerClient** — Docker Engine API client over Unix socket (`~/.arcbox/run/docker.sock`)
- **Packages/K8sClient** — Kubernetes API client with kubeconfig + exec-based auth
- Daemon (`arcbox-daemon`) is a separate Rust binary from the `../arcbox` repo; communicates via gRPC over `~/.arcbox/run/arcbox.sock`
- Entitlements for the daemon live in `../arcbox/bundle/arcbox.entitlements` (single source of truth)

## Code Style
- Swift 6 strict concurrency (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`)
- ViewModels use `@Observable`; environment injection via custom `EnvironmentKey`
- Logging: use the `Log` enum (OSLog-based) in the app, `ClientLog` in Packages
- Prefer `async/await` over Combine; use `Task.detached` only for Sendable-isolated gRPC calls
- No Combine, no third-party UI libraries; only external deps: Sparkle, SwiftTerm, Sentry
- Imports: Foundation/SwiftUI first, then local packages, then third-party; one blank line before body
