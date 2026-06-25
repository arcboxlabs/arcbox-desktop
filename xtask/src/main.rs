//! ArcBox desktop repository automation.
//!
//! `main.rs` only defines the CLI surface and dispatches into `commands`.
//! All task logic lives in the per-domain modules under `commands/`.

use std::path::PathBuf;

use anyhow::Result;
use clap::{Args, Parser, Subcommand};

mod commands;
#[cfg(target_os = "macos")]
mod support;

#[derive(Parser)]
#[command(author, version, about = "ArcBox desktop repository automation")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// macOS build, bundling, signing, and packaging tasks.
    Macos(MacosArgs),
    /// ArcBox protocol client generation and verification tasks.
    Protocol(ProtocolArgs),
    /// Release metadata generation (Sparkle appcast, latest.json).
    Release(ReleaseArgs),
}

// ── macos ────────────────────────────────────────────────────────────────────

#[derive(Args)]
struct MacosArgs {
    #[command(subcommand)]
    command: MacosCommand,
}

#[derive(Subcommand)]
enum MacosCommand {
    /// Embed arcbox Rust binaries into the app bundle (Xcode build phase).
    Embed(MacosEmbedArgs),
    /// Bundle the arcbox-daemon binary into a minimal signed `.app`.
    Bundle(MacosBundleArgs),
    /// Build, sign, notarize, and package `ArcBox.app` into a DMG.
    Dmg(MacosDmgArgs),
}

/// All inputs come from the Xcode build environment; there are no flags.
#[derive(Args)]
struct MacosEmbedArgs {}

#[derive(Args)]
struct MacosBundleArgs {
    /// Path to the arcbox-daemon Mach-O binary.
    daemon_binary: PathBuf,
    /// Directory to create the `.app` bundle in (e.g. `Contents/Frameworks`).
    output_dir: PathBuf,
    /// Path to a `.provisionprofile` to embed.
    #[arg(long)]
    provisioning_profile: Option<PathBuf>,
    /// Codesign identity (e.g. "Developer ID Application: ..."). Ad-hoc when omitted.
    #[arg(long)]
    sign: Option<String>,
    /// Path to an entitlements plist for the daemon.
    #[arg(long)]
    entitlements: Option<PathBuf>,
    /// CFBundleVersion / CFBundleShortVersionString.
    #[arg(long, default_value = "1.0")]
    version: String,
}

#[derive(Args)]
struct MacosDmgArgs {
    /// Codesign identity. When omitted the app is left ad-hoc/unsigned.
    #[arg(long)]
    sign: Option<String>,
    /// Notarize and staple the DMG after signing.
    #[arg(long)]
    notarize: bool,
    /// Provisioning profile embedded into the daemon bundle.
    #[arg(long)]
    provisioning_profile: Option<PathBuf>,
    /// Release version (defaults to MARKETING_VERSION in Version.xcconfig).
    #[arg(long, env = "VERSION")]
    version: Option<String>,
    /// Path to the arcbox checkout (auto-discovered when unset).
    #[arg(long, env = "ARCBOX_DIR")]
    arcbox_dir: Option<PathBuf>,
    /// Sparkle appcast feed URL injected into Info.plist.
    #[arg(long, env = "SPARKLE_FEED_URL")]
    sparkle_feed_url: Option<String>,
    /// PostHog product-analytics key injected into Info.plist.
    #[arg(long, env = "POSTHOG_API_KEY")]
    posthog_api_key: Option<String>,
    /// Sentry DSN injected into Info.plist.
    #[arg(long, env = "SENTRY_DSN")]
    sentry_dsn: Option<String>,
    /// Sparkle EdDSA public key injected into Info.plist (SUPublicEDKey).
    #[arg(long, env = "SPARKLE_PUBLIC_KEY")]
    sparkle_public_key: Option<String>,
}

// ── protocol ────────────────────────────────────────────────────────────────

#[derive(Args)]
struct ProtocolArgs {
    #[command(subcommand)]
    command: ProtocolCommand,
}

#[derive(Subcommand)]
enum ProtocolCommand {
    /// Update arcbox.version and regenerate the Swift protobuf client atomically.
    Bump(ProtocolBumpArgs),
    /// Verify the generated Swift protobuf client matches arcbox.version.
    Verify(ProtocolVerifyArgs),
}

#[derive(Args)]
struct ProtocolBumpArgs {
    /// Embedded arcbox daemon version tag, e.g. v0.4.12.
    #[arg(long, env = "VERSION")]
    version: String,
}

#[derive(Args)]
struct ProtocolVerifyArgs {}

// ── release ────────────────────────────────────────────────────────────────--

#[derive(Args)]
struct ReleaseArgs {
    #[command(subcommand)]
    command: ReleaseCommand,
}

#[derive(Subcommand)]
enum ReleaseCommand {
    /// Resolve build version, channel, prerelease flag, and arcbox ref into GITHUB_OUTPUT.
    Resolve(ReleaseResolveArgs),
    /// Generate or update a Sparkle 2.x appcast XML feed.
    Appcast(ReleaseAppcastArgs),
    /// Update (or create) the latest.json channel manifest.
    LatestJson(ReleaseLatestJsonArgs),
}

#[derive(Args)]
struct ReleaseResolveArgs {
    /// Workflow input: arcbox repo ref (branch/tag/SHA). Empty or "master" falls back
    /// to arcbox.version, then "master".
    #[arg(long, default_value = "")]
    arcbox_ref: String,
    /// Workflow input: explicit version tag (e.g. v1.2.0). Empty derives the version.
    #[arg(long, default_value = "")]
    tag: String,
    /// GitHub event name (push | workflow_dispatch).
    #[arg(long, env = "GITHUB_EVENT_NAME", default_value = "")]
    event_name: String,
    /// Git ref (e.g. refs/tags/v1.2.0 on a tag push).
    #[arg(long, env = "GITHUB_REF", default_value = "")]
    github_ref: String,
}

#[derive(Args)]
struct ReleaseAppcastArgs {
    /// Release version (leading "v" is stripped automatically).
    #[arg(long)]
    version: String,
    /// CFBundleVersion build number.
    #[arg(long)]
    build_number: String,
    /// Download URL for the DMG.
    #[arg(long)]
    dmg_url: String,
    /// DMG file size in bytes.
    #[arg(long)]
    dmg_length: String,
    /// EdDSA (ed25519) signature of the DMG.
    #[arg(long)]
    ed_signature: String,
    /// Sparkle channel.
    #[arg(long, default_value = "stable")]
    channel: String,
    /// Minimum macOS version.
    #[arg(long, default_value = "15.0")]
    min_macos: String,
    /// Output appcast XML path.
    #[arg(long)]
    output: PathBuf,
    /// Existing appcast to merge the new item into.
    #[arg(long)]
    existing: Option<PathBuf>,
    /// HTML file embedded as the item description (falls back to a GitHub release link).
    #[arg(long)]
    release_notes_html: Option<PathBuf>,
}

#[derive(Args)]
struct ReleaseLatestJsonArgs {
    /// Release version (leading "v" is stripped automatically).
    #[arg(long)]
    version: String,
    /// Update channel name.
    #[arg(long, default_value = "stable")]
    channel: String,
    /// Path to write the resulting latest.json.
    #[arg(long)]
    output: PathBuf,
    /// Existing latest.json to merge channels from.
    #[arg(long)]
    existing: Option<PathBuf>,
}

fn main() {
    if let Err(error) = run() {
        if let Some(exit) = error.downcast_ref::<xtask_kit::process::ExitCode>() {
            std::process::exit(exit.code());
        }
        eprintln!("Error: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    match Cli::parse().command {
        Command::Macos(args) => commands::macos::run(args),
        Command::Protocol(args) => commands::protocol::run(args),
        Command::Release(args) => commands::release::run(args),
    }
}
