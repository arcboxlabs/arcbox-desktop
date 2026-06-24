//! Bundle the arcbox-daemon binary into a minimal `.app`.
//!
//! Ported from the former `bundle-daemon.py`. The daemon gets its own
//! `Contents/embedded.provisionprofile` so AMFI can validate restricted
//! entitlements (virtualization/hypervisor) on the user's machine.
//!
//! `bundle_daemon` is also called in-process by the `embed` and `dmg`
//! commands, replacing the previous `subprocess` call into the Python script.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use xtask_kit::apple::{self, CodesignOptions};
use xtask_kit::process;

use crate::MacosBundleArgs;

const BUNDLE_ID: &str = "com.arcboxlabs.desktop.daemon";
const BUNDLE_NAME: &str = "ArcBox Daemon";
const EXECUTABLE_NAME: &str = "com.arcboxlabs.desktop.daemon";

const REQUIRED_ENTITLEMENTS: [&str; 2] = [
    "com.apple.security.virtualization",
    "com.apple.security.hypervisor",
];

/// Inputs for [`bundle_daemon`].
pub struct BundleOptions<'a> {
    pub daemon_binary: &'a Path,
    pub output_dir: &'a Path,
    pub provisioning_profile: Option<&'a Path>,
    pub sign_identity: Option<&'a str>,
    pub entitlements: Option<&'a Path>,
    pub version: &'a str,
}

fn write_info_plist(contents: &Path, version: &str) -> Result<()> {
    let mut dict = plist::Dictionary::new();
    dict.insert("CFBundleIdentifier".into(), BUNDLE_ID.into());
    dict.insert("CFBundleExecutable".into(), EXECUTABLE_NAME.into());
    dict.insert("CFBundleName".into(), BUNDLE_NAME.into());
    dict.insert("CFBundlePackageType".into(), "APPL".into());
    dict.insert("CFBundleInfoDictionaryVersion".into(), "6.0".into());
    dict.insert("CFBundleVersion".into(), version.into());
    dict.insert("CFBundleShortVersionString".into(), version.into());
    dict.insert(
        "CFBundleSupportedPlatforms".into(),
        plist::Value::Array(vec!["MacOSX".into()]),
    );
    dict.insert("LSUIElement".into(), plist::Value::Boolean(true));

    let plist_path = contents.join("Info.plist");
    plist::Value::from(dict)
        .to_file_xml(&plist_path)
        .with_context(|| format!("writing {}", plist_path.display()))?;
    Ok(())
}

/// Create the daemon `.app` bundle and return its path.
pub fn bundle_daemon(opts: &BundleOptions<'_>) -> Result<PathBuf> {
    let bundle_dir = opts.output_dir.join(format!("{EXECUTABLE_NAME}.app"));
    let contents = bundle_dir.join("Contents");
    let macos_dir = contents.join("MacOS");

    if bundle_dir.exists() {
        std::fs::remove_dir_all(&bundle_dir)
            .with_context(|| format!("removing {}", bundle_dir.display()))?;
    }
    std::fs::create_dir_all(&macos_dir)
        .with_context(|| format!("creating {}", macos_dir.display()))?;

    // 1. Copy daemon binary.
    let dest_binary = macos_dir.join(EXECUTABLE_NAME);
    std::fs::copy(opts.daemon_binary, &dest_binary).with_context(|| {
        format!(
            "copying {} -> {}",
            opts.daemon_binary.display(),
            dest_binary.display()
        )
    })?;
    std::fs::set_permissions(&dest_binary, std::fs::Permissions::from_mode(0o755))
        .with_context(|| format!("chmod {}", dest_binary.display()))?;
    println!("  Copied daemon binary → {}", dest_binary.display());

    // 2. Info.plist + PkgInfo.
    write_info_plist(&contents, opts.version)?;
    std::fs::write(contents.join("PkgInfo"), "APPL????").context("writing PkgInfo")?;
    println!("  Created Info.plist (version={})", opts.version);

    // 3. Embed provisioning profile.
    if let Some(profile) = opts.provisioning_profile {
        let dest = contents.join("embedded.provisionprofile");
        std::fs::copy(profile, &dest)
            .with_context(|| format!("embedding {}", profile.display()))?;
        println!("  Embedded provisioning profile → {}", dest.display());
    }

    // 4. Sign the bundle.
    match opts.sign_identity {
        Some(identity) => {
            let mut options = CodesignOptions::runtime(identity, &bundle_dir);
            options.entitlements = opts.entitlements;
            apple::codesign(&options)?;

            apple::verify_signature(&bundle_dir)
                .context("daemon bundle signature verification failed")?;
            if opts.entitlements.is_some() {
                let xml = apple::entitlements_xml(&bundle_dir)?;
                for ent in REQUIRED_ENTITLEMENTS {
                    if !xml.contains(ent) {
                        bail!("{} missing entitlement {ent}", bundle_dir.display());
                    }
                }
            }
            println!("  Signed daemon bundle with identity: {identity}");
        }
        None => {
            // Ad-hoc deep sign for local dev.
            let sh = process::shell()?;
            let bundle = &bundle_dir;
            xshell::cmd!(sh, "codesign --force --deep -s - {bundle}")
                .run()
                .context("ad-hoc signing daemon bundle")?;
            println!("  Ad-hoc signed daemon bundle");
        }
    }

    Ok(bundle_dir)
}

pub fn run(args: MacosBundleArgs) -> Result<()> {
    if !args.daemon_binary.is_file() {
        bail!("daemon binary not found: {}", args.daemon_binary.display());
    }
    if let Some(profile) = &args.provisioning_profile {
        if !profile.is_file() {
            bail!("provisioning profile not found: {}", profile.display());
        }
    }
    if let Some(entitlements) = &args.entitlements {
        if !entitlements.is_file() {
            bail!("entitlements not found: {}", entitlements.display());
        }
    }

    std::fs::create_dir_all(&args.output_dir)
        .with_context(|| format!("creating {}", args.output_dir.display()))?;

    let bundle = bundle_daemon(&BundleOptions {
        daemon_binary: &args.daemon_binary,
        output_dir: &args.output_dir,
        provisioning_profile: args.provisioning_profile.as_deref(),
        sign_identity: args.sign.as_deref(),
        entitlements: args.entitlements.as_deref(),
        version: &args.version,
    })?;
    println!("  Bundle: {}", bundle.display());
    Ok(())
}
