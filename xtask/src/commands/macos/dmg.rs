//! Build `ArcBox.app` and package it into a signed/notarized DMG.
//!
//! Ported from the former `package-dmg.py`. Orchestrates xcodebuild, embeds the
//! arcbox binaries / boot assets / runtime / completions, bundles + signs the
//! daemon, deep-signs the app, builds the DMG, and notarizes it.
//!
//! It also injects the custom telemetry Info.plist keys (PostHogAPIKey,
//! SentryDSN, SUPublicEDKey) via `plutil`-style writes — `INFOPLIST_KEY_*`
//! build settings silently drop custom keys, which left product analytics
//! disabled in shipped builds.

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use xtask_kit::apple::{self, CodesignOptions};
use xtask_kit::dmg::{self, CreateDmgOptions};
use xtask_kit::{github_actions, process, repo};

use super::bundle::{self, BundleOptions, BundleProfile};
use super::{ABCTL_CODE_SIGN_IDENTIFIER, HELPER_CODE_SIGN_IDENTIFIER};
use crate::support::fs as xfs;
use crate::{MacosDmgArgs, MacosPrepareResourcesArgs};

const SCHEME_NAME: &str = "ArcBox";
const PRODUCTION_DAEMON_NAME: &str = "com.arcboxlabs.desktop.daemon";
const DOCKER_TOOLS: [&str; 4] = [
    "docker",
    "docker-buildx",
    "docker-compose",
    "docker-credential-osxkeychain",
];

const HOST_ARCH: &str = "arm64";

struct ResourceOptions<'a> {
    force: bool,
    boot_assets_dir: Option<&'a Path>,
    boot_assets_kernel: Option<&'a Path>,
    boot_assets_rootfs: Option<&'a Path>,
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

fn profile_home(profile: BundleProfile) -> PathBuf {
    home().join(profile.data_dir_name())
}

/// Sign a binary with hardened runtime; no-op when `identity` is empty.
fn sign_binary(target: &Path, identity: &str) -> Result<()> {
    if identity.is_empty() {
        return Ok(());
    }
    apple::codesign(&CodesignOptions::runtime(identity, target))
}

/// Sign a binary with the stable identifier expected by helper peer auth.
fn sign_binary_with_identifier(target: &Path, identity: &str, identifier: &str) -> Result<()> {
    if identity.is_empty() {
        return Ok(());
    }
    let mut options = CodesignOptions::runtime(identity, target);
    options.identifier = Some(identifier);
    apple::codesign(&options)
}

fn desktop_repo() -> Result<PathBuf> {
    if let Ok(dir) = std::env::var("DESKTOP_REPO") {
        if !dir.is_empty() {
            return Ok(PathBuf::from(dir));
        }
    }
    repo::root_from_xtask_manifest(env!("CARGO_MANIFEST_DIR"))
}

fn resolve_arcbox_dir(desktop_repo: &Path, arg: Option<&Path>) -> Result<PathBuf> {
    if let Some(dir) = arg {
        return Ok(dir.to_path_buf());
    }
    for candidate in [
        desktop_repo.join("arcbox"),
        desktop_repo
            .parent()
            .map(|p| p.join("arcbox"))
            .unwrap_or_default(),
    ] {
        if candidate.is_dir() {
            return Ok(candidate);
        }
    }
    bail!("cannot locate arcbox checkout (set ARCBOX_DIR)")
}

fn read_version(desktop_repo: &Path, arg: Option<&str>) -> Result<String> {
    let raw = match arg {
        Some(v) if !v.is_empty() => v.to_string(),
        _ => {
            let xcconfig = desktop_repo.join("Version.xcconfig");
            let text = std::fs::read_to_string(&xcconfig).unwrap_or_default();
            let version = text.lines().find_map(|line| {
                let line = line.trim();
                let rest = line.strip_prefix("MARKETING_VERSION")?;
                let rest = rest.trim_start();
                let rest = rest.strip_prefix('=')?;
                // Drop trailing `// comment`.
                let value = rest.split("//").next().unwrap_or("").trim();
                (!value.is_empty()).then(|| value.to_string())
            });
            version.unwrap_or_else(|| "0.0.0".to_string())
        }
    };
    Ok(raw.trim_start_matches('v').to_string())
}

fn git_commit_count(repo: &Path) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(["rev-list", "--count", "HEAD"])
        .output()
        .context("running git rev-list")?;
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn build_swift_app(
    desktop_repo: &Path,
    arcbox_dir: &Path,
    profile: BundleProfile,
    build_number: &str,
    sign_identity: &str,
    skip_xcode_embed: bool,
) -> Result<PathBuf> {
    println!("--- Building Swift app ---");
    let derived_data = desktop_repo.join(".build").join("DerivedData");
    let spm_clones = desktop_repo.join(".build").join("SourcePackages");

    let mut cmd = Command::new("xcodebuild");
    cmd.arg("build")
        .arg("-project")
        .arg(desktop_repo.join("ArcBox.xcodeproj"))
        .args(["-scheme", SCHEME_NAME, "-configuration", "Release"])
        .arg("-showBuildTimingSummary")
        .arg("-derivedDataPath")
        .arg(&derived_data)
        .arg("-clonedSourcePackagesDirPath")
        .arg(&spm_clones)
        .arg("-skipPackagePluginValidation")
        .arg("ARCHS=arm64")
        .arg(format!("ARCBOX_DIR={}", arcbox_dir.display()))
        .arg(format!("CURRENT_PROJECT_VERSION={build_number}"));
    if profile == BundleProfile::Development {
        cmd.arg(format!(
            "ARCBOX_PRODUCT_BUNDLE_IDENTIFIER={}",
            profile.product_bundle_identifier()
        ))
        .arg(format!("ARCBOX_PRODUCT_NAME={}", profile.app_name()))
        .arg(format!("ARCBOX_APP_DISPLAY_NAME={}", profile.app_name()))
        .arg(format!("ARCBOX_PROFILE={}", profile.arcbox_profile()));
    }
    if !sign_identity.is_empty() {
        cmd.arg(format!("CODE_SIGN_IDENTITY={sign_identity}"))
            .arg("CODE_SIGN_STYLE=Manual");
    }
    // Packaging re-embeds host/guest binaries after the Swift build. Skipping
    // the Xcode embed phase avoids a second copy/sign pass (and any residual
    // cargo work) during CI release builds.
    if skip_xcode_embed {
        cmd.env("SKIP_RUST_BUILD", "1");
        println!("  SKIP_RUST_BUILD=1 (packaging will embed binaries)");
    }

    let status = cmd.status().context("running xcodebuild")?;
    if !status.success() {
        bail!("xcodebuild failed");
    }

    let products = derived_data.join("Build").join("Products").join("Release");
    let app = std::fs::read_dir(&products)
        .with_context(|| format!("reading {}", products.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .find(|p| p.extension().is_some_and(|ext| ext == "app"));
    app.with_context(|| format!(".app bundle not found in {}", products.display()))
}

fn inject_sparkle_feed_url(app_bundle: &Path, url: Option<&str>) -> Result<()> {
    let Some(url) = url.filter(|u| !u.is_empty()) else {
        return Ok(());
    };
    let plist = app_bundle.join("Contents").join("Info.plist");
    apple::set_plist_string(&plist, "SUFeedURL", url)?;
    println!("  SUFeedURL: {url}");
    Ok(())
}

/// Inject custom telemetry keys that `INFOPLIST_KEY_*` cannot deliver.
fn inject_telemetry_keys(app_bundle: &Path, args: &MacosDmgArgs) -> Result<()> {
    let plist = app_bundle.join("Contents").join("Info.plist");
    let entries = [
        ("PostHogAPIKey", args.posthog_api_key.as_deref()),
        ("SentryDSN", args.sentry_dsn.as_deref()),
        ("SUPublicEDKey", args.sparkle_public_key.as_deref()),
    ];
    for (key, value) in entries {
        if let Some(value) = value.filter(|v| !v.is_empty()) {
            apple::set_plist_string(&plist, key, value)?;
            println!("  {key}: <injected>");
        }
    }
    Ok(())
}

fn inject_profile_key(app_bundle: &Path, profile: BundleProfile) -> Result<()> {
    let plist = app_bundle.join("Contents").join("Info.plist");
    apple::set_plist_string(&plist, "ArcBoxProfile", profile.arcbox_profile())?;
    println!("  ArcBoxProfile: {}", profile.arcbox_profile());
    Ok(())
}

fn read_boot_version(lock_file: &Path) -> Result<String> {
    let text = std::fs::read_to_string(lock_file)
        .with_context(|| format!("reading {}", lock_file.display()))?;
    let mut in_boot = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed == "[boot]" {
            in_boot = true;
            continue;
        }
        if in_boot && trimmed.starts_with("version") {
            if let Some(start) = line.find('"') {
                if let Some(end) = line[start + 1..].find('"') {
                    return Ok(line[start + 1..start + 1 + end].to_string());
                }
            }
        }
    }
    bail!("cannot parse boot version from {}", lock_file.display())
}

fn run_abctl_profile_command(
    abctl: &Path,
    profile: BundleProfile,
    args: &[&str],
    description: &str,
) -> Result<()> {
    println!(
        "  Running abctl --profile {} {description}...",
        profile.arcbox_profile()
    );
    let status = Command::new(abctl)
        .args(["--profile", profile.arcbox_profile()])
        .args(args)
        .status()
        .with_context(|| format!("running abctl {description}"))?;
    if !status.success() {
        bail!("abctl {description} failed");
    }
    Ok(())
}

fn run_abctl_profile_command_owned(
    abctl: &Path,
    profile: BundleProfile,
    args: &[String],
    description: &str,
) -> Result<()> {
    println!(
        "  Running abctl --profile {} {description}...",
        profile.arcbox_profile()
    );
    let status = Command::new(abctl)
        .args(["--profile", profile.arcbox_profile()])
        .args(args)
        .status()
        .with_context(|| format!("running abctl {description}"))?;
    if !status.success() {
        bail!("abctl {description} failed");
    }
    Ok(())
}

fn build_boot_assets_tool(boot_assets_dir: &Path) -> Result<PathBuf> {
    println!("  Building local boot-assets CLI...");
    let status = Command::new("cargo")
        .args([
            "build",
            "--release",
            "--features",
            "build",
            "--no-default-features",
        ])
        .current_dir(boot_assets_dir)
        .status()
        .context("building local boot-assets CLI")?;
    if !status.success() {
        bail!("cargo build for local boot-assets failed");
    }

    let tool = boot_assets_dir
        .join("target")
        .join("release")
        .join("boot-assets");
    if !tool.is_file() {
        bail!("boot-assets CLI was not built at {}", tool.display());
    }
    Ok(tool)
}

fn resolve_boot_assets_kernel(
    desktop_repo: &Path,
    boot_assets_dir: &Path,
    explicit: Option<&Path>,
) -> Result<PathBuf> {
    if let Some(kernel) = explicit {
        if kernel.is_file() {
            return Ok(kernel.to_path_buf());
        }
        bail!("boot-assets kernel not found: {}", kernel.display());
    }

    let candidates = [
        boot_assets_dir.join("build").join("kernel-arm64"),
        boot_assets_dir.join("build").join("kernel"),
        boot_assets_dir
            .parent()
            .map(|p| p.join("kernel").join("output").join("kernel-arm64"))
            .unwrap_or_default(),
        desktop_repo
            .parent()
            .map(|p| p.join("kernel").join("output").join("kernel-arm64"))
            .unwrap_or_default(),
    ];
    candidates
        .into_iter()
        .find(|p| p.is_file())
        .with_context(|| {
            format!(
                "cannot find a kernel for local boot-assets build; pass --boot-assets-kernel or place one under {}/build/kernel-arm64",
                boot_assets_dir.display()
            )
        })
}

fn unpack_boot_assets_tarball(tarball: &Path, dest: &Path) -> Result<()> {
    std::fs::create_dir_all(dest).with_context(|| format!("creating {}", dest.display()))?;
    let status = Command::new("/usr/bin/tar")
        .args(["-xzf"])
        .arg(tarball)
        .arg("-C")
        .arg(dest)
        .status()
        .with_context(|| format!("extracting {}", tarball.display()))?;
    if !status.success() {
        bail!("extracting {} failed", tarball.display());
    }
    for name in ["manifest.json", "kernel", "rootfs.erofs"] {
        let path = dest.join(name);
        if !path.is_file() {
            bail!(
                "local boot-assets tarball did not contain {}",
                path.display()
            );
        }
    }
    Ok(())
}

fn boot_cache_ready(cache_dir: &Path) -> bool {
    cache_dir.join("manifest.json").is_file()
        && cache_dir.join("kernel").is_file()
        && cache_dir.join("rootfs.erofs").is_file()
}

fn build_local_boot_assets(
    desktop_repo: &Path,
    arcbox_dir: &Path,
    profile: BundleProfile,
    opts: &ResourceOptions<'_>,
) -> Result<()> {
    let Some(boot_assets_dir) = opts.boot_assets_dir else {
        return Ok(());
    };
    println!("--- Building local boot-assets ---");
    if !boot_assets_dir.join("Cargo.toml").is_file() {
        bail!(
            "boot-assets checkout not found: {}",
            boot_assets_dir.display()
        );
    }

    let version = read_boot_version(&arcbox_dir.join("assets.lock"))?;
    let cache_dir = profile_home(profile).join("boot").join(&version);
    if !opts.force && boot_cache_ready(&cache_dir) {
        println!(
            "  Local boot-assets already prepared at {}",
            cache_dir.display()
        );
        return Ok(());
    }

    let output_dir = boot_assets_dir.join("dist").join(HOST_ARCH);
    if opts.force && output_dir.exists() {
        std::fs::remove_dir_all(&output_dir)
            .with_context(|| format!("removing {}", output_dir.display()))?;
    }

    let tool = build_boot_assets_tool(boot_assets_dir)?;
    let kernel =
        resolve_boot_assets_kernel(desktop_repo, boot_assets_dir, opts.boot_assets_kernel)?;
    let mut args = vec![
        "build".to_string(),
        "release".to_string(),
        "--version".to_string(),
        version.clone(),
        "--kernel".to_string(),
        kernel.display().to_string(),
        "--arch".to_string(),
        HOST_ARCH.to_string(),
        "--output-dir".to_string(),
        output_dir.display().to_string(),
        "--source-repo".to_string(),
        "local/boot-assets".to_string(),
    ];
    if let Some(rootfs) = opts.boot_assets_rootfs {
        if !rootfs.is_file() {
            bail!("boot-assets rootfs not found: {}", rootfs.display());
        }
        args.push("--rootfs".to_string());
        args.push(rootfs.display().to_string());
    }

    let status = Command::new(&tool)
        .args(&args)
        .current_dir(boot_assets_dir)
        .status()
        .context("building local boot assets")?;
    if !status.success() {
        bail!("local boot-assets build failed");
    }

    let tarball = output_dir.join(format!("boot-assets-{HOST_ARCH}-v{version}.tar.gz"));
    if !tarball.is_file() {
        bail!("local boot-assets tarball not found: {}", tarball.display());
    }
    if cache_dir.exists() {
        std::fs::remove_dir_all(&cache_dir)
            .with_context(|| format!("removing {}", cache_dir.display()))?;
    }
    unpack_boot_assets_tarball(&tarball, &cache_dir)?;
    println!("  Installed local boot-assets → {}", cache_dir.display());
    Ok(())
}

fn prepare_profile_resources(
    desktop_repo: &Path,
    arcbox_dir: &Path,
    profile: BundleProfile,
    opts: &ResourceOptions<'_>,
) -> Result<()> {
    println!("--- Preparing profile resources ---");
    let abctl = arcbox_dir.join("target").join("release").join("abctl");
    if !abctl.is_file() {
        bail!(
            "abctl not found at {}. The Xcode build should have built local arcbox binaries first.",
            abctl.display()
        );
    }

    if opts.force {
        let runtime_dir = profile_home(profile).join("runtime");
        if runtime_dir.exists() {
            std::fs::remove_dir_all(&runtime_dir)
                .with_context(|| format!("removing {}", runtime_dir.display()))?;
        }
    }

    if opts.boot_assets_dir.is_some() {
        build_local_boot_assets(desktop_repo, arcbox_dir, profile, opts)?;
    } else {
        let mut boot_args = vec!["boot".to_string(), "prefetch".to_string()];
        if opts.force {
            boot_args.push("--force".to_string());
        }
        run_abctl_profile_command_owned(&abctl, profile, &boot_args, "boot prefetch")?;
    }
    run_abctl_profile_command(&abctl, profile, &["docker", "setup"], "docker setup")?;
    Ok(())
}

fn embed_boot_assets(app_bundle: &Path, arcbox_dir: &Path, profile: BundleProfile) -> Result<()> {
    println!("--- Embedding boot-assets ---");
    let lock_file = arcbox_dir.join("assets.lock");
    let boot_version = read_boot_version(&lock_file)?;
    println!("  Boot-asset version: {boot_version}");

    let boot_cache = [
        arcbox_dir
            .join("target")
            .join("boot-assets")
            .join(&boot_version),
        profile_home(profile).join("boot").join(&boot_version),
    ]
    .into_iter()
    .find(|c| c.join("manifest.json").is_file());

    let boot_cache = boot_cache.with_context(|| {
        format!("boot-assets v{boot_version} not found. Run 'abctl boot prefetch' first.")
    })?;

    let resources = app_bundle.join("Contents").join("Resources");
    std::fs::copy(&lock_file, resources.join("assets.lock")).context("copying assets.lock")?;

    let boot_dest = resources.join("assets").join(&boot_version);
    std::fs::create_dir_all(&boot_dest)
        .with_context(|| format!("creating {}", boot_dest.display()))?;
    for name in ["kernel", "rootfs.erofs", "manifest.json"] {
        std::fs::copy(boot_cache.join(name), boot_dest.join(name))
            .with_context(|| format!("copying boot asset {name}"))?;
    }
    println!(
        "  Embedded boot-assets from {} → {}",
        boot_cache.display(),
        boot_dest.display()
    );
    Ok(())
}

fn embed_host_cli_binaries(
    app_bundle: &Path,
    arcbox_dir: &Path,
    sign_identity: &str,
) -> Result<()> {
    let src_dir = arcbox_dir.join("target").join("release");
    let bin_dir = app_bundle.join("Contents").join("MacOS").join("bin");
    std::fs::create_dir_all(&bin_dir)?;

    // abctl is required for boot/docker tooling inside the shipped app.
    let abctl_src = src_dir.join("abctl");
    if !abctl_src.is_file() {
        bail!("abctl not found at {}", abctl_src.display());
    }
    println!("--- Embedding host CLI binaries ---");
    let abctl_dst = bin_dir.join("abctl");
    std::fs::copy(&abctl_src, &abctl_dst).context("copying abctl")?;
    sign_binary_with_identifier(&abctl_dst, sign_identity, ABCTL_CODE_SIGN_IDENTIFIER)?;
    println!("  Copied abctl → MacOS/bin/abctl");

    // Desktop startup requires the bundled helper for installation and version
    // verification, so release packaging must fail rather than ship without it.
    let helper_src = src_dir.join("arcbox-helper");
    if !helper_src.is_file() {
        bail!(
            "required arcbox-helper not found at {}; Desktop startup cannot continue without it",
            helper_src.display()
        );
    }
    let helper_dst = bin_dir.join("arcbox-helper");
    std::fs::copy(&helper_src, &helper_dst).context("copying arcbox-helper")?;
    sign_binary_with_identifier(&helper_dst, sign_identity, HELPER_CODE_SIGN_IDENTIFIER)?;
    println!("  Copied arcbox-helper → MacOS/bin/arcbox-helper");
    Ok(())
}

/// Embed the Linux guest binaries — arcbox-agent (System VM agent) and
/// vm-agent (sandbox microVM init) — which the daemon seeds from
/// Resources/bin into <data_dir>/bin at startup.
fn embed_guest_binaries(app_bundle: &Path, arcbox_dir: &Path) -> Result<()> {
    println!("--- Embedding guest binaries ---");
    let src_dir = arcbox_dir
        .join("target")
        .join("aarch64-unknown-linux-musl")
        .join("release");
    let dest_dir = app_bundle.join("Contents").join("Resources").join("bin");
    std::fs::create_dir_all(&dest_dir)?;
    for name in ["arcbox-agent", "vm-agent"] {
        let src = src_dir.join(name);
        if !src.is_file() {
            println!("  Warning: {name} not found at {}", src.display());
            continue;
        }
        let dest = dest_dir.join(name);
        std::fs::copy(&src, &dest).with_context(|| format!("copying {name}"))?;
        strip_binary_best_effort(&dest);
        println!("  Copied {name} → Resources/bin/{name}");
    }
    Ok(())
}

fn embed_docker_tools(
    app_bundle: &Path,
    sign_identity: &str,
    profile: BundleProfile,
) -> Result<()> {
    println!("--- Embedding Docker CLI tools ---");
    let src_dir = profile_home(profile).join("runtime").join("bin");
    let dest_dir = app_bundle.join("Contents").join("MacOS").join("xbin");
    std::fs::create_dir_all(&dest_dir)?;
    let mut count = 0;
    for tool in DOCKER_TOOLS {
        let src = src_dir.join(tool);
        if src.is_file() {
            let dst = dest_dir.join(tool);
            std::fs::copy(&src, &dst).with_context(|| format!("copying {tool}"))?;
            // Strip before codesign. Go CLIs often ship with symbol tables;
            // only keep the stripped file when it actually got smaller.
            strip_binary_best_effort(&dst);
            sign_binary(&dst, sign_identity)?;
            println!("  Embedded {tool} → MacOS/xbin/{tool}");
            count += 1;
        }
    }
    if count == 0 {
        println!("  Warning: no Docker tools found at {}", src_dir.display());
        let _ = std::fs::remove_dir(&dest_dir);
    }
    Ok(())
}

fn embed_runtime(app_bundle: &Path, sign_identity: &str, profile: BundleProfile) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    println!("--- Embedding runtime binaries ---");

    let runtime_src = profile_home(profile).join("runtime");
    let runtime_dest = app_bundle
        .join("Contents")
        .join("Resources")
        .join("runtime");
    let mut count = 0;
    if runtime_src.is_dir() {
        for entry in walkdir::WalkDir::new(&runtime_src).follow_links(false) {
            let entry = entry.context("walking runtime dir")?;
            if !entry.file_type().is_file() {
                continue;
            }
            // Only executable files (skip .sha256, .tmp, etc.).
            let mode = entry
                .metadata()
                .context("stat runtime file")?
                .permissions()
                .mode();
            if mode & 0o111 == 0 {
                continue;
            }
            let rel = entry
                .path()
                .strip_prefix(&runtime_src)
                .expect("under runtime_src");
            // Host Docker CLI tools are installed into ~/.arcbox/runtime/bin by
            // `abctl docker setup` for non-bundle PATH use, and separately
            // embedded into MacOS/xbin for /usr/local/bin symlinks. They are
            // Mach-O and useless inside the guest VirtioFS seed — skip them so
            // the DMG does not ship a second ~130MB copy.
            if xfs::is_macho(entry.path()) {
                println!(
                    "  Skipping host binary {} (MacOS/xbin holds Docker CLI)",
                    rel.display()
                );
                continue;
            }
            let dest = runtime_dest.join(rel);
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::copy(entry.path(), &dest)
                .with_context(|| format!("copying runtime file {}", rel.display()))?;
            // Drop DWARF / symbol tables from guest ELFs before codesign.
            // Upstream dockerd/runc/firecracker releases often ship unstripped.
            strip_binary_best_effort(&dest);
            sign_binary(&dest, sign_identity)?;
            println!("  Embedded {}", rel.display());
            count += 1;
        }
    }
    if count == 0 {
        println!(
            "  Warning: no runtime binaries found at {}",
            runtime_src.display()
        );
        let _ = std::fs::remove_dir_all(&runtime_dest);
    }
    Ok(())
}

/// Whether `name` resolves to an executable on `PATH` (or is an absolute path).
fn command_exists(name: &str) -> bool {
    if name.contains('/') {
        return Path::new(name).is_file();
    }
    std::env::var_os("PATH")
        .map(|paths| {
            std::env::split_paths(&paths).any(|dir| {
                let candidate = dir.join(name);
                candidate.is_file()
            })
        })
        .unwrap_or(false)
}

/// Candidate strip tools for `path`, ordered by preference for its format.
///
/// - Mach-O: Apple `/usr/bin/strip` first.
/// - ELF (Linux guest): prefer ELF-capable cross/LLVM strippers. Apple's
///   cctools `strip` handles some simple ELFs but fails on others (e.g.
///   statically-linked Go `dockerd` with a broken `.rela.plt` link field).
fn strip_tool_candidates(path: &Path) -> Vec<&'static str> {
    let candidates: &[&str] = if xfs::is_macho(path) {
        &["/usr/bin/strip", "strip"]
    } else if xfs::is_elf(path) {
        &[
            "llvm-strip",
            "aarch64-linux-musl-strip",
            "aarch64-linux-gnu-strip",
            "aarch64-unknown-linux-gnu-strip",
            // Last resorts: PATH strip / Apple strip (may work on simple ELFs).
            "strip",
            "/usr/bin/strip",
        ]
    } else {
        return Vec::new();
    };
    candidates
        .iter()
        .copied()
        .filter(|name| command_exists(name) || Path::new(name).is_file())
        .collect()
}

/// Best-effort `strip` for Mach-O / ELF payloads embedded in the app bundle.
///
/// - No-op for non-binary files (e.g. Linux kernel Image).
/// - Tries each candidate tool on a temp copy; keeps the first result that is
///   strictly smaller than the original (so tools that grow under strip, or
///   that fail on a particular binary, are skipped).
/// - Failures are logged and ignored — a larger binary beats a broken pack.
fn strip_binary_best_effort(path: &Path) {
    let tools = strip_tool_candidates(path);
    if tools.is_empty() {
        return;
    }
    let before = match std::fs::metadata(path) {
        Ok(m) => m.len(),
        Err(_) => return,
    };
    let tmp = path.with_extension("strip-tmp");
    let mut last_err: Option<String> = None;

    for tool in tools {
        if let Err(e) = std::fs::copy(path, &tmp) {
            println!("  Warning: strip prepare {}: {e}", path.display());
            return;
        }
        match Command::new(tool).arg(&tmp).status() {
            Ok(s) if s.success() => {
                let after = std::fs::metadata(&tmp).map(|m| m.len()).unwrap_or(before);
                if after < before {
                    if let Err(e) = std::fs::rename(&tmp, path) {
                        println!("  Warning: strip install {}: {e}", path.display());
                        let _ = std::fs::remove_file(&tmp);
                        return;
                    }
                    println!(
                        "  Stripped {} with {tool} ({:.1} → {:.1} MB)",
                        path.file_name().and_then(|n| n.to_str()).unwrap_or("?"),
                        before as f64 / (1024.0 * 1024.0),
                        after as f64 / (1024.0 * 1024.0)
                    );
                    return;
                }
                // Tool ran but did not shrink — try the next candidate.
                let _ = std::fs::remove_file(&tmp);
            }
            Ok(s) => {
                let _ = std::fs::remove_file(&tmp);
                last_err = Some(format!("{tool} exited {}", s.code().unwrap_or(-1)));
            }
            Err(e) => {
                let _ = std::fs::remove_file(&tmp);
                last_err = Some(format!("{tool}: {e}"));
            }
        }
    }

    if let Some(err) = last_err {
        println!("  Warning: could not strip {}: {err}", path.display());
    }
}

/// Strip the main app executable if Xcode left local symbols in place.
/// dSYMs (when produced) remain beside DerivedData for crash symbolication.
fn strip_app_executable(app_bundle: &Path, profile: BundleProfile) {
    println!("--- Stripping app executable ---");
    let exe = app_bundle
        .join("Contents")
        .join("MacOS")
        .join(profile.app_name());
    if exe.is_file() {
        strip_binary_best_effort(&exe);
    } else {
        println!("  Warning: app executable not found at {}", exe.display());
    }
}

fn embed_completions(app_bundle: &Path) -> Result<()> {
    println!("--- Generating and embedding Docker completions ---");
    let docker_bin = app_bundle
        .join("Contents")
        .join("MacOS")
        .join("xbin")
        .join("docker");
    let comp_dest = app_bundle
        .join("Contents")
        .join("Resources")
        .join("completions");
    if !docker_bin.is_file() {
        println!("  Warning: docker binary not found in app bundle, cannot generate completions");
        return Ok(());
    }
    for (shell, filename) in [
        ("bash", "docker"),
        ("zsh", "_docker"),
        ("fish", "docker.fish"),
    ] {
        let output = Command::new(&docker_bin)
            .args(["completion", shell])
            .output()
            .with_context(|| format!("running docker completion {shell}"))?;
        if output.status.success() && !output.stdout.is_empty() {
            let dest_dir = comp_dest.join(shell);
            std::fs::create_dir_all(&dest_dir)?;
            std::fs::write(dest_dir.join(filename), &output.stdout)
                .with_context(|| format!("writing {shell} completion"))?;
            println!("  Generated {shell} completion → {filename}");
        } else {
            println!(
                "  Warning: docker completion {shell} failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            );
        }
    }
    Ok(())
}

fn embed_pstramp(app_bundle: &Path, arcbox_dir: &Path, sign_identity: &str) -> Result<()> {
    println!("--- Embedding pstramp ---");
    let mut candidates = Vec::new();
    if let Ok(dir) = std::env::var("PSTRAMP_DIR") {
        if !dir.is_empty() {
            candidates.push(
                PathBuf::from(dir)
                    .join("target")
                    .join("release")
                    .join("pstramp"),
            );
        }
    }
    if let Some(parent) = arcbox_dir.parent() {
        candidates.push(
            parent
                .join("pstramp")
                .join("target")
                .join("release")
                .join("pstramp"),
        );
    }

    match candidates.into_iter().find(|c| c.is_file()) {
        Some(src) => {
            let dst = app_bundle.join("Contents").join("MacOS").join("pstramp");
            std::fs::copy(&src, &dst).context("copying pstramp")?;
            sign_binary(&dst, sign_identity)?;
            println!("  Embedded pstramp from {}", src.display());
        }
        None => println!(
            "  Warning: pstramp not found. Build it with: cargo build --release -p pstramp"
        ),
    }
    Ok(())
}

fn bundle_daemon_step(
    app_bundle: &Path,
    arcbox_dir: &Path,
    profile: BundleProfile,
    version: &str,
    sign_identity: &str,
    provisioning_profile: Option<&Path>,
) -> Result<()> {
    println!("--- Bundling daemon ---");
    let daemon_name = profile.daemon_label();
    let frameworks = app_bundle.join("Contents").join("Frameworks");
    let already_bundled = frameworks
        .join(format!("{daemon_name}.app"))
        .join("Contents")
        .join("MacOS")
        .join(daemon_name);

    // Locate the daemon binary from possible locations; if Xcode already
    // bundled it, copy the binary out before bundle_daemon wipes the bundle.
    let stash;
    let daemon_src: PathBuf = if already_bundled.is_file() {
        let tmp = tempfile::NamedTempFile::new().context("creating temp file")?;
        std::fs::copy(&already_bundled, tmp.path()).context("stashing daemon binary")?;
        stash = Some(tmp);
        stash.as_ref().unwrap().path().to_path_buf()
    } else {
        stash = None;
        let helpers = app_bundle
            .join("Contents")
            .join("Helpers")
            .join(daemon_name);
        let target_release = arcbox_dir
            .join("target")
            .join("release")
            .join("arcbox-daemon");
        if helpers.is_file() {
            helpers
        } else if target_release.is_file() {
            target_release
        } else {
            bail!("cannot locate arcbox-daemon binary");
        }
    };

    let entitlements = arcbox_dir
        .join("bundle")
        .join(profile.daemon_entitlements_file());
    bundle::bundle_daemon(&BundleOptions {
        profile,
        daemon_binary: &daemon_src,
        output_dir: &frameworks,
        provisioning_profile,
        sign_identity: (!sign_identity.is_empty()).then_some(sign_identity),
        entitlements: (!sign_identity.is_empty()).then_some(entitlements.as_path()),
        version,
    })?;
    drop(stash);

    // Remove legacy bare binary if Xcode put it in Helpers/.
    let legacy = app_bundle
        .join("Contents")
        .join("Helpers")
        .join(daemon_name);
    let _ = std::fs::remove_file(&legacy);
    let _ = std::fs::remove_dir(app_bundle.join("Contents").join("Helpers"));
    Ok(())
}

fn sign_app_bundle(
    app_bundle: &Path,
    desktop_repo: &Path,
    profile: BundleProfile,
    sign_identity: &str,
    build_dir: &Path,
) -> Result<()> {
    println!("--- Signing app bundle ---");
    let sh = process::shell()?;
    let daemon_name = profile.daemon_label();
    let daemon_bundle = app_bundle
        .join("Contents")
        .join("Frameworks")
        .join(format!("{daemon_name}.app"));

    // Stash daemon bundle to preserve its signature + provisioning profile.
    let stash_dir = if daemon_bundle.is_dir() {
        let dir = tempfile::tempdir_in(build_dir).context("creating stash dir")?;
        let stashed = dir.path().join(format!("{daemon_name}.app"));
        std::fs::rename(&daemon_bundle, &stashed).context("stashing daemon bundle")?;
        println!("  Stashed daemon bundle to preserve signature + profile");
        Some((dir, stashed))
    } else {
        None
    };

    // Deep-sign the entire app bundle.
    xshell::cmd!(
        sh,
        "codesign --force --deep --options runtime --sign {sign_identity} --timestamp {app_bundle}"
    )
    .run()
    .context("deep-signing app bundle")?;

    // Restore pre-signed daemon bundle.
    if let Some((_dir, stashed)) = &stash_dir {
        std::fs::rename(stashed, &daemon_bundle).context("restoring daemon bundle")?;
        println!("  Restored pre-signed daemon bundle");
    }

    // `codesign --deep` derives standalone executable identifiers from their
    // basenames. Restore the stable identifiers that helper peer auth checks.
    let host_bin_dir = app_bundle.join("Contents").join("MacOS").join("bin");
    for (name, identifier) in [
        ("abctl", ABCTL_CODE_SIGN_IDENTIFIER),
        ("arcbox-helper", HELPER_CODE_SIGN_IDENTIFIER),
    ] {
        let binary = host_bin_dir.join(name);
        if !binary.is_file() {
            bail!("required bundled binary missing at {}", binary.display());
        }
        sign_binary_with_identifier(&binary, sign_identity, identifier)?;
        println!("  Re-signed {name} as {identifier}");
    }

    // Re-sign ArcBoxHelper.
    let helper = app_bundle
        .join("Contents")
        .join("Library")
        .join("HelperTools")
        .join("ArcBoxHelper");
    if helper.is_file() {
        let entitlements = desktop_repo
            .join("ArcBoxHelper")
            .join("ArcBoxHelper.entitlements");
        let mut options = CodesignOptions::runtime(sign_identity, &helper);
        options.identifier = Some(HELPER_CODE_SIGN_IDENTIFIER);
        options.entitlements = Some(&entitlements);
        apple::codesign(&options)?;
        println!("  Signed ArcBoxHelper with hardened runtime");
    }

    // Re-sign the outer app (nested code changed, seal must be refreshed).
    let app_entitlements = desktop_repo.join("ArcBox").join("ArcBox.entitlements");
    let mut options = CodesignOptions::runtime(sign_identity, app_bundle);
    options.entitlements = Some(&app_entitlements);
    apple::codesign(&options)?;

    xshell::cmd!(sh, "codesign --verify --deep --strict {app_bundle}")
        .run()
        .context("verifying app bundle signature")?;
    println!("  Signed and verified");
    Ok(())
}

fn create_dmg(app_bundle: &Path, dmg_path: &Path, profile: BundleProfile) -> Result<()> {
    println!("--- Creating DMG ---");
    let options = CreateDmgOptions::new(profile.app_name(), app_bundle, dmg_path);
    dmg::create(&options)
}

fn rewrite_launch_agent_plist(app_bundle: &Path, profile: BundleProfile) -> Result<()> {
    let launch_agents = app_bundle
        .join("Contents")
        .join("Library")
        .join("LaunchAgents");
    let production_plist = launch_agents.join(format!("{PRODUCTION_DAEMON_NAME}.plist"));
    let daemon_name = profile.daemon_label();
    let profile_plist = launch_agents.join(format!("{daemon_name}.plist"));

    if !production_plist.is_file() {
        return Ok(());
    }

    if profile == BundleProfile::Development {
        std::fs::rename(&production_plist, &profile_plist).with_context(|| {
            format!(
                "renaming {} -> {}",
                production_plist.display(),
                profile_plist.display()
            )
        })?;
    }

    let plist_path = if profile == BundleProfile::Development {
        &profile_plist
    } else {
        &production_plist
    };

    let mut value = plist::Value::from_file(plist_path)
        .with_context(|| format!("reading {}", plist_path.display()))?;
    let dict = value
        .as_dictionary_mut()
        .context("LaunchAgent plist root is not a dictionary")?;
    dict.insert("Label".into(), daemon_name.into());
    dict.insert(
        "BundleProgram".into(),
        format!("Contents/Frameworks/{daemon_name}.app/Contents/MacOS/{daemon_name}").into(),
    );
    dict.insert(
        "ProgramArguments".into(),
        plist::Value::Array(vec![
            daemon_name.into(),
            "--profile".into(),
            profile.arcbox_profile().into(),
            "--docker-integration".into(),
        ]),
    );
    dict.insert(
        "StandardOutPath".into(),
        format!("/tmp/{daemon_name}.stdout.log").into(),
    );
    dict.insert(
        "StandardErrorPath".into(),
        format!("/tmp/{daemon_name}.stderr.log").into(),
    );
    value
        .to_file_xml(plist_path)
        .with_context(|| format!("writing {}", plist_path.display()))?;
    Ok(())
}

pub fn prepare_resources_command(args: MacosPrepareResourcesArgs) -> Result<()> {
    let desktop_repo = desktop_repo()?;
    let arcbox_dir = resolve_arcbox_dir(&desktop_repo, args.arcbox_dir.as_deref())?;
    let profile = BundleProfile::from_dev_flag(args.dev);
    let resource_options = ResourceOptions {
        force: args.force,
        boot_assets_dir: args.boot_assets_dir.as_deref(),
        boot_assets_kernel: args.boot_assets_kernel.as_deref(),
        boot_assets_rootfs: args.boot_assets_rootfs.as_deref(),
    };

    println!("=== Preparing ArcBox resources ===");
    println!("  Desktop repo : {}", desktop_repo.display());
    println!("  Arcbox dir   : {}", arcbox_dir.display());
    println!("  Profile      : {}", profile.arcbox_profile());
    println!("  Force        : {}", args.force);
    if let Some(dir) = args.boot_assets_dir.as_deref() {
        println!("  Boot assets  : {}", dir.display());
    }

    prepare_profile_resources(&desktop_repo, &arcbox_dir, profile, &resource_options)
}

pub fn run(args: MacosDmgArgs) -> Result<()> {
    let desktop_repo = desktop_repo()?;
    let arcbox_dir = resolve_arcbox_dir(&desktop_repo, args.arcbox_dir.as_deref())?;
    let profile = BundleProfile::from_dev_flag(args.dev);
    let resource_options = ResourceOptions {
        force: args.force_resources,
        boot_assets_dir: args.boot_assets_dir.as_deref(),
        boot_assets_kernel: args.boot_assets_kernel.as_deref(),
        boot_assets_rootfs: args.boot_assets_rootfs.as_deref(),
    };
    let sign_identity = args.sign.clone().unwrap_or_default();

    let version = read_version(&desktop_repo, args.version.as_deref())?;
    let build_number = git_commit_count(&desktop_repo)?;

    let build_dir = arcbox_dir.join("target").join("dmg-build");
    let app_bundle = build_dir.join(format!("{}.app", profile.app_name()));
    let dmg_name = if profile == BundleProfile::Development {
        format!("ArcBox-Dev-{version}-arm64")
    } else {
        format!("ArcBox-{version}-arm64")
    };
    let dmg_path = arcbox_dir.join("target").join(format!("{dmg_name}.dmg"));

    println!("=== Building ArcBox ===");
    println!("  Desktop repo : {}", desktop_repo.display());
    println!("  Arcbox dir   : {}", arcbox_dir.display());
    println!("  Profile      : {}", profile.arcbox_profile());
    println!("  Version      : {version}");
    println!("  Build number : {build_number}");
    println!(
        "  Sign identity: {}",
        if sign_identity.is_empty() {
            "(ad-hoc)"
        } else {
            &sign_identity
        }
    );
    println!("  Notarize     : {}", args.notarize);
    println!("  Skip resources: {}", args.skip_resources);
    println!("  Skip Xcode embed: {}", args.skip_xcode_embed);

    // 1. Build Swift app, then copy to staging.
    let built_app = build_swift_app(
        &desktop_repo,
        &arcbox_dir,
        profile,
        &build_number,
        &sign_identity,
        args.skip_xcode_embed,
    )?;
    if app_bundle.exists() {
        std::fs::remove_dir_all(&app_bundle)
            .with_context(|| format!("removing {}", app_bundle.display()))?;
    }
    std::fs::create_dir_all(&build_dir)?;
    xfs::copy_tree(&built_app, &app_bundle)?;
    println!("  App bundle: {}", app_bundle.display());

    inject_sparkle_feed_url(&app_bundle, args.sparkle_feed_url.as_deref())?;
    inject_telemetry_keys(&app_bundle, &args)?;
    inject_profile_key(&app_bundle, profile)?;

    if args.skip_resources {
        println!("--- Skipping profile resource prefetch (already prepared) ---");
    } else {
        prepare_profile_resources(&desktop_repo, &arcbox_dir, profile, &resource_options)?;
    }
    embed_boot_assets(&app_bundle, &arcbox_dir, profile)?;
    embed_host_cli_binaries(&app_bundle, &arcbox_dir, &sign_identity)?;
    embed_guest_binaries(&app_bundle, &arcbox_dir)?;
    embed_docker_tools(&app_bundle, &sign_identity, profile)?;
    embed_runtime(&app_bundle, &sign_identity, profile)?;
    embed_completions(&app_bundle)?;
    embed_pstramp(&app_bundle, &arcbox_dir, &sign_identity)?;
    bundle_daemon_step(
        &app_bundle,
        &arcbox_dir,
        profile,
        &version,
        &sign_identity,
        args.provisioning_profile.as_deref(),
    )?;
    rewrite_launch_agent_plist(&app_bundle, profile)?;

    if !sign_identity.is_empty() {
        // Strip only when we will re-sign below. Mutating the Xcode-signed
        // main binary without a subsequent codesign invalidates the seal
        // (local/ad-hoc DMGs use an empty identity and skip re-sign).
        // Release also sets STRIP_INSTALLED_PRODUCT so Xcode usually already
        // stripped; this is a belt-and-suspenders pass for leftover symbols.
        strip_app_executable(&app_bundle, profile);
        sign_app_bundle(
            &app_bundle,
            &desktop_repo,
            profile,
            &sign_identity,
            &build_dir,
        )?;
    }

    create_dmg(&app_bundle, &dmg_path, profile)?;
    if !sign_identity.is_empty() {
        dmg::sign(&sign_identity, &dmg_path)?;
    }
    if args.notarize && !sign_identity.is_empty() {
        apple::notarize_and_staple(&dmg_path, "arcbox-notarize")?;
    }

    if let Ok(summary) = dmg::file_summary(&dmg_path) {
        println!("=== Done ===");
        println!("  DMG: {summary}");
    }

    // Expose artifact metadata to GitHub Actions (no-op outside CI).
    let dmg_basename = dmg_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or_default();
    github_actions::append_output_env("dmg", dmg_basename)?;
    github_actions::append_output_env("dmg_path", &dmg_path.display().to_string())?;
    github_actions::append_output_env("build_number", &build_number)?;
    Ok(())
}
