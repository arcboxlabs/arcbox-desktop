# xtask

Repository automation for arcbox-desktop. This is the single entry point for
release/packaging/codegen-style tasks that don't belong in the Swift/Xcode
build itself. It is a thin `clap` CLI over the shared
[`xtask`](https://crates.io/crates/xtask) building-block crate (imported as
`xtask-kit`), mirroring the layout used by `../arcbox/xtask`.

## Running

`cargo xtask <command>` runs from the repo root via the `.cargo/config.toml`
alias (`xtask = "run --quiet --manifest-path xtask/Cargo.toml --"`). The crate is
a **standalone workspace** — it keeps no Cargo.toml/Cargo.lock at the (Swift)
repo root and never joins a parent `cargo build`. Requires a Rust toolchain on
`PATH` (`devenv shell` provides one; CI installs it via `dtolnay/rust-toolchain`).

```sh
cargo xtask release appcast --help
cargo xtask protocol bump --version v0.4.12
cargo xtask macos dmg --sign "Developer ID Application: …" --notarize
```

## Commands

| Command | Purpose |
| --- | --- |
| `macos embed` | Embed arcbox Rust binaries into the app bundle. Runs from the Xcode "Embed Arcbox Binaries" build phase; env-driven (`PROJECT_DIR`, `BUILT_PRODUCTS_DIR`, `SKIP_RUST_BUILD`, …). |
| `macos bundle` | Wrap the `arcbox-daemon` binary in a minimal signed `.app` (its own `embedded.provisionprofile` for AMFI). |
| `macos dmg` | Build `ArcBox.app`, embed assets/binaries, bundle + sign the daemon, deep-sign, package the DMG, and notarize. Injects `PostHogAPIKey`/`SentryDSN`/`SUPublicEDKey` into Info.plist. |
| `protocol bump` | Update `arcbox.version` and regenerate the Swift protobuf client atomically. |
| `protocol verify` | Regenerate the Swift protobuf client from `arcbox.version` and fail if checked-in generated files drift. |
| `release appcast` | Generate or merge a Sparkle 2.x appcast XML feed. |
| `release latest-json` | Update the `latest.json` channel manifest. |

## Layout

```
src/
  main.rs                 CLI shape (clap) + dispatch only — no task logic
  commands/
    macos.rs              dispatch: embed / bundle / dmg (macOS-gated)
    macos/{embed,bundle,dmg}.rs
    protocol.rs           arcbox.version + protobuf client codegen
    release.rs            dispatch: appcast / latest-json
    release/{appcast,latest_json}.rs
  support/fs.rs           generic helpers shared by macOS commands
```

`main.rs` holds the argument structs and subcommand enums; domain modules import
them from `crate::`. macOS-only modules are `#[cfg(target_os = "macos")]` so the
crate still builds on Linux CI (where only the `release` commands run).

## Design rules

- **Structured formats use crates, never hand-rolled strings/shell**: `plist`
  for Info.plist, `serde_json` (via `xtask-kit`) for `latest.json`, `time` for
  timestamps, `sha2`/`xtask-kit::hash` for digests, `regex` for the appcast
  merge. `appcast` is implemented locally (not `xtask_kit::sparkle`) only
  because it needs the embedded release-notes `<description>` CDATA path.
- **Short external commands** (`codesign`, `security`, `make`) use `xshell`;
  long/streaming processes (`xcodebuild`) use `std::process::Command`.
- **Don't shell out to avoid a small, appropriate dependency.** Shell is for
  real external tools only (`codesign`, `xcrun`, `create-dmg`, `make`, …).
- **No thin wrappers.** `support/` holds only genuinely cross-command helpers
  (Mach-O detection, content-diff copy decisions, symlink-preserving tree copy);
  one-off logic stays inline.
- Reuse `xtask-kit` primitives (`apple`, `dmg`, `latest_json`, `hash`,
  `github_actions`, `fs`, `repo`, `process`) rather than reimplementing them.
