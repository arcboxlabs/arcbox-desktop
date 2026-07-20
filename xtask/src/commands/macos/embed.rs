//! Embed arcbox Rust binaries into the Xcode app bundle (build phase).
//!
//! Ported from the former `embed-arcbox-binaries.py`. Driven entirely by the
//! Xcode build environment. Builds the Rust binaries (incremental), copies them
//! into the app bundle (skipping unchanged files), signs the CLI/helper with
//! Xcode's identity, and bundles + signs the daemon with a Developer ID
//! certificate (required for virtualization/hypervisor entitlements).

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use regex::Regex;
use xtask_kit::apple::{self, CodesignOptions};

use super::bundle::{self, BundleOptions, BundleProfile};
use super::{ABCTL_CODE_SIGN_IDENTIFIER, HELPER_CODE_SIGN_IDENTIFIER};
use crate::MacosEmbedArgs;
use crate::support::fs as xfs;

const REQUIRED_ENTITLEMENTS: [&str; 2] = [
    "com.apple.security.virtualization",
    "com.apple.security.hypervisor",
];

fn env(key: &str) -> String {
    std::env::var(key).unwrap_or_default()
}

fn note(msg: &str) {
    println!("note: {msg}");
}

fn warn(msg: &str) {
    println!("warning: {msg}");
}

/// PATH that makes cargo/make/homebrew tools reachable; Xcode strips PATH.
fn augmented_path() -> String {
    let home = env("HOME");
    let existing = env("PATH");
    format!("{home}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:{existing}")
}

/// Sign a non-daemon binary with Xcode's build identity (or ad-hoc).
fn sign_with_xcode_identity(target: &Path, identifier: &str) -> Result<()> {
    let expanded = env("EXPANDED_CODE_SIGN_IDENTITY");
    let code_sign = env("CODE_SIGN_IDENTITY");

    let options = if !expanded.is_empty() && expanded != "-" {
        let mut o = CodesignOptions::runtime(&expanded, target);
        o.identifier = Some(identifier);
        o
    } else if !code_sign.is_empty() && code_sign != "-" {
        let mut o = CodesignOptions::runtime(&code_sign, target);
        o.identifier = Some(identifier);
        o.timestamp = false;
        o
    } else {
        // Ad-hoc: no hardened runtime, no identifier, no timestamp.
        CodesignOptions {
            identity: "-",
            target,
            entitlements: None,
            identifier: None,
            hardened_runtime: false,
            timestamp: false,
        }
    };
    apple::codesign(&options)
}

/// Copy `src` to `dst` only if content differs; returns `true` when copied.
fn sync_binary(src: &Path, dst: &Path) -> Result<bool> {
    if !xfs::needs_copy(src, dst)? {
        return Ok(false);
    }
    std::fs::copy(src, dst)
        .with_context(|| format!("copying {} -> {}", src.display(), dst.display()))?;
    Ok(true)
}

/// Find a Developer ID identity (returns SHA-1 hash to avoid name ambiguity).
fn find_developer_id(preferred_org: Option<&str>) -> Result<Option<String>> {
    let override_id = env("DAEMON_SIGN_IDENTITY");
    if !override_id.is_empty() {
        return Ok(Some(override_id));
    }

    let output = Command::new("/usr/bin/security")
        .args(["find-identity", "-v", "-p", "codesigning"])
        .output()
        .context("running security find-identity")?;
    if !output.status.success() {
        return Ok(None);
    }
    let stdout = String::from_utf8_lossy(&output.stdout);

    let pattern =
        Regex::new(r#"(?m)^\s*\d+\)\s+([A-F0-9]{40})\s+"(Developer ID Application: [^"]+)""#)
            .context("compiling identity regex")?;
    let candidates: Vec<(String, String)> = pattern
        .captures_iter(&stdout)
        .map(|c| (c[1].to_string(), c[2].to_string()))
        .collect();

    if candidates.is_empty() {
        return Ok(None);
    }
    if let Some(org) = preferred_org {
        for (sha1, name) in &candidates {
            if name.contains(org) {
                return Ok(Some(sha1.clone()));
            }
        }
    }
    Ok(Some(candidates[0].0.clone()))
}

fn find_arcbox_repo(project_dir: &Path) -> Option<PathBuf> {
    let override_dir = env("ARCBOX_DIR");
    if !override_dir.is_empty() {
        return Some(PathBuf::from(override_dir));
    }
    [
        project_dir.join("arcbox"),
        parent_join(project_dir, "arcbox"),
    ]
    .into_iter()
    .find(|candidate| candidate.join("Cargo.toml").is_file())
}

fn parent_join(dir: &Path, name: &str) -> PathBuf {
    match dir.parent() {
        Some(parent) => parent.join(name),
        None => PathBuf::from(name),
    }
}

pub fn run(_args: MacosEmbedArgs) -> Result<()> {
    if env("SKIP_RUST_BUILD") == "1" {
        note("SKIP_RUST_BUILD=1, skipping binary embedding");
        return Ok(());
    }

    let path = augmented_path();
    let project_dir = PathBuf::from(if env("PROJECT_DIR").is_empty() {
        ".".to_string()
    } else {
        env("PROJECT_DIR")
    })
    .canonicalize()
    .context("resolving PROJECT_DIR")?;
    let built_products = PathBuf::from(env("BUILT_PRODUCTS_DIR"));
    let contents_folder = env("CONTENTS_FOLDER_PATH");

    let version = std::fs::read_to_string(project_dir.join("arcbox.version"))
        .context("reading arcbox.version")?
        .trim()
        .to_string();
    let cache_dir = project_dir
        .join(".build")
        .join("arcbox-binaries")
        .join(&version);

    let arcbox_repo = find_arcbox_repo(&project_dir);
    let profile = BundleProfile::from_environment();
    let daemon_name = profile.daemon_label();
    // Host binaries dir + guest (Linux musl) binaries dir of a local checkout.
    let local_dirs = arcbox_repo.as_ref().map(|r| {
        (
            r.join("target").join("release"),
            r.join("target")
                .join("aarch64-unknown-linux-musl")
                .join("release"),
        )
    });

    // ── Build (incremental) ──────────────────────────────────────────────────
    // Skip cargo when host release binaries are already present (CI prebuilt
    // path, or a prior local `make build-rust`). Rebuilding here was the main
    // release-pipeline regression: ~9 minutes of redundant compile after the
    // workflow had already downloaded release tarballs.
    let host_bins_ready = local_dirs.as_ref().is_some_and(|(local, _)| {
        let abctl = local.join("abctl");
        let daemon = local.join("arcbox-daemon");
        abctl.is_file() && daemon.is_file() && xfs::is_macho(&daemon)
    });
    if let Some(repo) = &arcbox_repo {
        if repo.join("Makefile").is_file() {
            if host_bins_ready {
                note("Local arcbox binaries already present; skipping make build-rust");
            } else {
                note("Building arcbox binaries (incremental)...");
                let status = Command::new("make")
                    .args(["-C"])
                    .arg(&project_dir)
                    .arg("build-rust")
                    .arg(format!("ARCBOX_DIR={}", repo.display()))
                    .env("PATH", &path)
                    .status()
                    .context("running make build-rust")?;
                if !status.success() {
                    bail!("make build-rust failed");
                }
            }
        }
    }

    // ── Resolve source ───────────────────────────────────────────────────────
    let (src_dir, guest_bin_dir): (PathBuf, PathBuf) =
        if let Some((local, local_guest)) = &local_dirs {
            if local.join("abctl").is_file() && local.join("arcbox-daemon").is_file() {
                if !xfs::is_macho(&local.join("arcbox-daemon")) {
                    bail!(
                        "{}/arcbox-daemon is not a valid Mach-O binary",
                        local.display()
                    );
                }
                note(&format!(
                    "Using local arcbox binaries from {}",
                    local.display()
                ));
                (local.clone(), local_guest.clone())
            } else {
                resolve_cache(&cache_dir, &version, &project_dir)?
            }
        } else {
            resolve_cache(&cache_dir, &version, &project_dir)?
        };

    // ── Embed daemon → Contents/Frameworks/*.app ──────────────────────────────
    let frameworks_dir = built_products.join(&contents_folder).join("Frameworks");
    let daemon_bundle = frameworks_dir.join(format!("{daemon_name}.app"));
    let daemon_binary = daemon_bundle
        .join("Contents")
        .join("MacOS")
        .join(daemon_name);
    let src_daemon = src_dir.join("arcbox-daemon");

    let daemon_identity = find_developer_id(Some("ArcBox, Inc."))?;
    if daemon_identity.is_none() {
        warn("No Developer ID signing identity found for daemon.");
        warn("  Daemon will use ad-hoc signing — restricted entitlements will NOT work.");
        warn("  Install a Developer ID certificate or set DAEMON_SIGN_IDENTITY.");
    }

    if xfs::needs_copy(&src_daemon, &daemon_binary)? {
        note("Building daemon .app bundle...");
        let entitlements = arcbox_repo
            .as_ref()
            .map(|r| r.join("bundle").join(profile.daemon_entitlements_file()))
            .filter(|p| {
                if daemon_identity.is_some() && !p.is_file() {
                    warn(&format!("Entitlements file not found at {}", p.display()));
                }
                p.is_file()
            });
        bundle::bundle_daemon(&BundleOptions {
            profile,
            daemon_binary: &src_daemon,
            output_dir: &frameworks_dir,
            provisioning_profile: None,
            sign_identity: daemon_identity.as_deref(),
            entitlements: daemon_identity.as_ref().and(entitlements.as_deref()),
            version: &version,
        })?;
        note(&format!(
            "Daemon bundle created at {}",
            daemon_bundle.display()
        ));
    } else {
        note("Daemon bundle unchanged, skipping rebuild");
    }

    // Verify daemon signature + entitlements.
    if daemon_identity.is_some() {
        apple::verify_signature(&daemon_binary).with_context(|| {
            format!(
                "daemon at {} has invalid signature",
                daemon_binary.display()
            )
        })?;
        let xml = apple::entitlements_xml(&daemon_binary)?;
        for ent in REQUIRED_ENTITLEMENTS {
            if !xml.contains(ent) {
                bail!(
                    "daemon at {} must be signed with Developer ID + entitlements (missing {ent})",
                    daemon_binary.display()
                );
            }
        }
    } else if apple::verify_signature(&daemon_binary).is_err() {
        warn(&format!(
            "{} has invalid or missing code signature",
            daemon_binary.display()
        ));
    }

    // Clean up legacy Helpers/ location.
    let legacy = built_products
        .join(&contents_folder)
        .join("Helpers")
        .join(daemon_name);
    if legacy.is_file() {
        std::fs::remove_file(&legacy).with_context(|| format!("removing {}", legacy.display()))?;
        note(&format!("Removed legacy daemon at Helpers/{daemon_name}"));
    }

    // ── Embed abctl → Contents/MacOS/bin/ ─────────────────────────────────────
    let cli_dir = built_products
        .join(&contents_folder)
        .join("MacOS")
        .join("bin");
    std::fs::create_dir_all(&cli_dir).with_context(|| format!("creating {}", cli_dir.display()))?;

    embed_signed_cli(
        &src_dir.join("abctl"),
        &cli_dir.join("abctl"),
        ABCTL_CODE_SIGN_IDENTIFIER,
        "abctl",
    )?;

    // ── Embed arcbox-helper → Contents/MacOS/bin/ ─────────────────────────────
    let helper_src = src_dir.join("arcbox-helper");
    if !helper_src.is_file() {
        bail!(
            "required arcbox-helper not found at {}; Desktop startup cannot continue without it",
            helper_src.display()
        );
    }
    embed_signed_cli(
        &helper_src,
        &cli_dir.join("arcbox-helper"),
        HELPER_CODE_SIGN_IDENTIFIER,
        "arcbox-helper",
    )?;

    // ── Embed guest binaries → Contents/Resources/bin/ ────────────────────────
    // arcbox-agent (System VM agent) and vm-agent (sandbox microVM init); the
    // daemon seeds both from Resources/bin into <data_dir>/bin at startup.
    let guest_dest = built_products
        .join(&contents_folder)
        .join("Resources")
        .join("bin");
    std::fs::create_dir_all(&guest_dest)
        .with_context(|| format!("creating {}", guest_dest.display()))?;
    for name in ["arcbox-agent", "vm-agent"] {
        let src = guest_bin_dir.join(name);
        if !src.is_file() {
            // Tolerated: pre-vm-agent release tarballs and partial local
            // builds; the daemon degrades gracefully without either binary.
            warn(&format!("{name} not found at {}, skipping", src.display()));
            continue;
        }
        if sync_binary(&src, &guest_dest.join(name))? {
            note(&format!("Embedded {name} → Resources/bin/{name}"));
        } else {
            note(&format!("{name} unchanged, skipping copy"));
        }
    }

    Ok(())
}

fn embed_signed_cli(src: &Path, dst: &Path, identifier: &str, label: &str) -> Result<()> {
    if sync_binary(src, dst)? {
        sign_with_xcode_identity(dst, identifier)?;
        note(&format!("Embedded and signed {label} → MacOS/bin/{label}"));
    } else {
        if apple::verify_signature(dst).is_err() {
            warn(&format!(
                "{label} signature invalid, consider cleaning build"
            ));
        }
        note(&format!("{label} unchanged, skipping copy"));
    }
    Ok(())
}

/// Returns (host binaries dir, guest binaries dir); the release tarball is
/// flat, so both point at the cache dir.
fn resolve_cache(
    cache_dir: &Path,
    version: &str,
    project_dir: &Path,
) -> Result<(PathBuf, PathBuf)> {
    if cache_dir.join("abctl").is_file() && cache_dir.join("arcbox-daemon").is_file() {
        if !xfs::is_macho(&cache_dir.join("arcbox-daemon")) {
            bail!(
                "cached arcbox-daemon is not a valid Mach-O binary.\n  Remove the stale cache and rebuild: rm -rf {}",
                cache_dir.display()
            );
        }
        note(&format!("Using cached arcbox {version} binaries"));
        Ok((cache_dir.to_path_buf(), cache_dir.to_path_buf()))
    } else {
        let arcbox_hint = parent_join(project_dir, "arcbox");
        bail!(
            "arcbox {version} binaries not found.\n\n\
             Option 1: Build from source\n  cd {} && cargo build --release\n\n\
             Option 2: Download {version} from GitHub Releases into\n    {}/",
            arcbox_hint.display(),
            cache_dir.display()
        );
    }
}
