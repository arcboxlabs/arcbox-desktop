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

use super::bundle::{self, BundleOptions};
use crate::MacosDmgArgs;
use crate::support::fs as xfs;

const APP_NAME: &str = "ArcBox";
const DAEMON_NAME: &str = "com.arcboxlabs.desktop.daemon";
const DOCKER_TOOLS: [&str; 4] = [
    "docker",
    "docker-buildx",
    "docker-compose",
    "docker-credential-osxkeychain",
];

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

/// Sign a binary with hardened runtime; no-op when `identity` is empty.
fn sign_binary(target: &Path, identity: &str) -> Result<()> {
    if identity.is_empty() {
        return Ok(());
    }
    apple::codesign(&CodesignOptions::runtime(identity, target))
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
    build_number: &str,
    sign_identity: &str,
) -> Result<PathBuf> {
    println!("--- Building Swift app ---");
    let derived_data = desktop_repo.join(".build").join("DerivedData");
    let spm_clones = PathBuf::from("/tmp/arcbox-spm-packages");

    let mut cmd = Command::new("xcodebuild");
    cmd.arg("build")
        .arg("-project")
        .arg(desktop_repo.join("ArcBox.xcodeproj"))
        .args(["-scheme", APP_NAME, "-configuration", "Release"])
        .arg("-derivedDataPath")
        .arg(&derived_data)
        .arg("-clonedSourcePackagesDirPath")
        .arg(&spm_clones)
        .arg("-skipPackagePluginValidation")
        .arg(format!("ARCBOX_DIR={}", arcbox_dir.display()))
        .arg(format!("CURRENT_PROJECT_VERSION={build_number}"));
    if !sign_identity.is_empty() {
        cmd.arg(format!("CODE_SIGN_IDENTITY={sign_identity}"))
            .arg("CODE_SIGN_STYLE=Manual");
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

fn embed_boot_assets(app_bundle: &Path, arcbox_dir: &Path) -> Result<()> {
    println!("--- Embedding boot-assets ---");
    let lock_file = arcbox_dir.join("assets.lock");
    let boot_version = read_boot_version(&lock_file)?;
    println!("  Boot-asset version: {boot_version}");

    let boot_cache = [
        arcbox_dir
            .join("target")
            .join("boot-assets")
            .join(&boot_version),
        home().join(".arcbox").join("boot").join(&boot_version),
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

fn embed_abctl(app_bundle: &Path, arcbox_dir: &Path, sign_identity: &str) -> Result<()> {
    let cli_bin = arcbox_dir.join("target").join("release").join("abctl");
    if !cli_bin.is_file() {
        return Ok(());
    }
    println!("--- Embedding abctl CLI ---");
    let bin_dir = app_bundle.join("Contents").join("MacOS").join("bin");
    std::fs::create_dir_all(&bin_dir)?;
    let dst = bin_dir.join("abctl");
    std::fs::copy(&cli_bin, &dst).context("copying abctl")?;
    sign_binary(&dst, sign_identity)?;
    println!("  Copied abctl → MacOS/bin/abctl");
    Ok(())
}

fn embed_agent(app_bundle: &Path, arcbox_dir: &Path) -> Result<()> {
    let agent_bin = arcbox_dir
        .join("target")
        .join("aarch64-unknown-linux-musl")
        .join("release")
        .join("arcbox-agent");
    if !agent_bin.is_file() {
        println!(
            "  Warning: arcbox-agent not found at {}",
            agent_bin.display()
        );
        return Ok(());
    }
    println!("--- Embedding arcbox-agent ---");
    let agent_dir = app_bundle.join("Contents").join("Resources").join("bin");
    std::fs::create_dir_all(&agent_dir)?;
    std::fs::copy(&agent_bin, agent_dir.join("arcbox-agent")).context("copying arcbox-agent")?;
    println!("  Copied arcbox-agent → Resources/bin/arcbox-agent");
    Ok(())
}

fn embed_docker_tools(app_bundle: &Path, sign_identity: &str) -> Result<()> {
    println!("--- Embedding Docker CLI tools ---");
    let src_dir = home().join(".arcbox").join("runtime").join("bin");
    let dest_dir = app_bundle.join("Contents").join("MacOS").join("xbin");
    std::fs::create_dir_all(&dest_dir)?;
    let mut count = 0;
    for tool in DOCKER_TOOLS {
        let src = src_dir.join(tool);
        if src.is_file() {
            let dst = dest_dir.join(tool);
            std::fs::copy(&src, &dst).with_context(|| format!("copying {tool}"))?;
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

fn embed_runtime(app_bundle: &Path, arcbox_dir: &Path, sign_identity: &str) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    println!("--- Preparing and embedding runtime binaries ---");

    let cli_bin = arcbox_dir.join("target").join("release").join("abctl");
    if cli_bin.is_file() {
        println!("  Running abctl boot prefetch...");
        let status = Command::new(&cli_bin)
            .args(["boot", "prefetch"])
            .status()
            .context("running abctl boot prefetch")?;
        if !status.success() {
            bail!("abctl boot prefetch failed");
        }
    } else {
        println!(
            "  Warning: abctl not found at {}, skipping prefetch",
            cli_bin.display()
        );
    }

    let runtime_src = home().join(".arcbox").join("runtime");
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
            let dest = runtime_dest.join(rel);
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::copy(entry.path(), &dest)
                .with_context(|| format!("copying runtime file {}", rel.display()))?;
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
    version: &str,
    sign_identity: &str,
    provisioning_profile: Option<&Path>,
) -> Result<()> {
    println!("--- Bundling daemon ---");
    let frameworks = app_bundle.join("Contents").join("Frameworks");
    let already_bundled = frameworks
        .join(format!("{DAEMON_NAME}.app"))
        .join("Contents")
        .join("MacOS")
        .join(DAEMON_NAME);

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
            .join(DAEMON_NAME);
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

    let entitlements = arcbox_dir.join("bundle").join("arcbox.entitlements");
    bundle::bundle_daemon(&BundleOptions {
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
        .join(DAEMON_NAME);
    let _ = std::fs::remove_file(&legacy);
    let _ = std::fs::remove_dir(app_bundle.join("Contents").join("Helpers"));
    Ok(())
}

fn sign_app_bundle(
    app_bundle: &Path,
    desktop_repo: &Path,
    sign_identity: &str,
    build_dir: &Path,
) -> Result<()> {
    println!("--- Signing app bundle ---");
    let sh = process::shell()?;
    let daemon_bundle = app_bundle
        .join("Contents")
        .join("Frameworks")
        .join(format!("{DAEMON_NAME}.app"));

    // Stash daemon bundle to preserve its signature + provisioning profile.
    let stash_dir = if daemon_bundle.is_dir() {
        let dir = tempfile::tempdir_in(build_dir).context("creating stash dir")?;
        let stashed = dir.path().join(format!("{DAEMON_NAME}.app"));
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
        options.identifier = Some("com.arcboxlabs.desktop.helper");
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

fn create_dmg(app_bundle: &Path, dmg_path: &Path) -> Result<()> {
    println!("--- Creating DMG ---");
    let options = CreateDmgOptions::new(APP_NAME, app_bundle, dmg_path);
    dmg::create(&options)
}

pub fn run(args: MacosDmgArgs) -> Result<()> {
    let desktop_repo = desktop_repo()?;
    let arcbox_dir = resolve_arcbox_dir(&desktop_repo, args.arcbox_dir.as_deref())?;
    let sign_identity = args.sign.clone().unwrap_or_default();

    let version = read_version(&desktop_repo, args.version.as_deref())?;
    let build_number = git_commit_count(&desktop_repo)?;

    let build_dir = arcbox_dir.join("target").join("dmg-build");
    let app_bundle = build_dir.join(format!("{APP_NAME}.app"));
    let dmg_name = format!("ArcBox-{version}-arm64");
    let dmg_path = arcbox_dir.join("target").join(format!("{dmg_name}.dmg"));

    println!("=== Building ArcBox ===");
    println!("  Desktop repo : {}", desktop_repo.display());
    println!("  Arcbox dir   : {}", arcbox_dir.display());
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

    // 1. Build Swift app, then copy to staging.
    let built_app = build_swift_app(&desktop_repo, &arcbox_dir, &build_number, &sign_identity)?;
    if app_bundle.exists() {
        std::fs::remove_dir_all(&app_bundle)
            .with_context(|| format!("removing {}", app_bundle.display()))?;
    }
    std::fs::create_dir_all(&build_dir)?;
    xfs::copy_tree(&built_app, &app_bundle)?;
    println!("  App bundle: {}", app_bundle.display());

    inject_sparkle_feed_url(&app_bundle, args.sparkle_feed_url.as_deref())?;
    inject_telemetry_keys(&app_bundle, &args)?;

    embed_boot_assets(&app_bundle, &arcbox_dir)?;
    embed_abctl(&app_bundle, &arcbox_dir, &sign_identity)?;
    embed_agent(&app_bundle, &arcbox_dir)?;
    embed_docker_tools(&app_bundle, &sign_identity)?;
    embed_runtime(&app_bundle, &arcbox_dir, &sign_identity)?;
    embed_completions(&app_bundle)?;
    embed_pstramp(&app_bundle, &arcbox_dir, &sign_identity)?;
    bundle_daemon_step(
        &app_bundle,
        &arcbox_dir,
        &version,
        &sign_identity,
        args.provisioning_profile.as_deref(),
    )?;

    if !sign_identity.is_empty() {
        sign_app_bundle(&app_bundle, &desktop_repo, &sign_identity, &build_dir)?;
    }

    create_dmg(&app_bundle, &dmg_path)?;
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
