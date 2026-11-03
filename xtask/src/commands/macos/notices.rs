//! Third-party notices in `Contents/Resources/ThirdPartyNotices`.
//!
//! The Xcode build copies the repository's hand-maintained `ThirdPartyNotices/`
//! directory: `components.json` describes every binary the bundle embeds from
//! outside this repository, next to the license texts it references. Packaging then
//! refuses a bundle whose shipped binaries that file does not describe at
//! exactly the shipped versions, and adds the notices it can generate:
//!
//! - `arcbox-NOTICE.md`, the arcbox checkout's cargo-about output for the Rust
//!   crates in the daemon, CLI, helper and guest agents;
//! - `swift-packages/<identity>/`, each resolved Swift package's license and
//!   notice files;
//! - `generated.json`, the groups for both, which the app reads after
//!   `components.json`.

use std::collections::BTreeSet;
use std::path::Path;

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

#[cfg(test)]
mod tests;

const NOTICES_DIR: &str = "ThirdPartyNotices";
const HOST_ARCH: &str = "arm64";

pub(super) fn embed(app_bundle: &Path, desktop_repo: &Path, arcbox_dir: &Path) -> Result<()> {
    println!("--- Embedding third-party notices ---");
    let resources = app_bundle.join("Contents").join("Resources");
    let notices = resources.join(NOTICES_DIR);

    let components = read_json(&notices.join("components.json"))?;
    let assets_lock = std::fs::read_to_string(resources.join("assets.lock"))
        .context("reading the bundled assets.lock")?;
    let boot_version = boot_version(&assets_lock)?;
    let manifest = read_json(
        &resources
            .join("assets")
            .join(&boot_version)
            .join("manifest.json"),
    )?;
    check_coverage(
        &shipped_keys(&assets_lock, &manifest)?,
        &covered_keys(&components),
    )?;

    let notice_md = arcbox_dir.join("NOTICE.md");
    std::fs::copy(&notice_md, notices.join("arcbox-NOTICE.md"))
        .with_context(|| format!("copying {}", notice_md.display()))?;
    let notice_text = std::fs::read_to_string(&notice_md)?;
    let arcbox_version = std::fs::read_to_string(resources.join("arcbox.version"))
        .context("reading the bundled arcbox.version")?;

    let resolved = desktop_repo
        .join("ArcBox.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved");
    let swift_packages = collect_swift_packages(
        &read_json(&resolved)?,
        &desktop_repo
            .join(".build")
            .join("SourcePackages")
            .join("checkouts"),
        &notices,
    )?;
    println!("  Swift packages: {}", swift_packages.len());

    let generated = json!({
        "groups": [
            {
                "id": "swift-packages",
                "title": "Swift packages",
                "summary": "The Swift packages compiled into the ArcBox app, at the versions in its Package.resolved.",
                "location": "ArcBox.app/Contents/MacOS/ArcBox and Contents/Frameworks",
                "components": swift_packages,
            },
            {
                "id": "rust-crates",
                "title": "Rust crates",
                "summary": "The Rust crates compiled into ArcBox's daemon, command-line tool, privileged helper and Linux guest agents. Each crate's source is published on crates.io; the list links each crate's repository.",
                "location": "ArcBox.app/Contents/MacOS/bin, Contents/Frameworks and Contents/Resources/bin",
                "components": [{
                    "name": "Rust crates in the ArcBox runtime",
                    "version": format!("arcbox {}", arcbox_version.trim()),
                    "license": cargo_about_licenses(&notice_text).join(", "),
                    "source": "https://github.com/arcboxlabs/arcbox",
                    "licenseFiles": ["arcbox-NOTICE.md"],
                }],
            },
        ]
    });
    std::fs::write(
        notices.join("generated.json"),
        serde_json::to_vec_pretty(&generated)?,
    )
    .context("writing generated.json")?;
    Ok(())
}

fn read_json(path: &Path) -> Result<Value> {
    let file = std::fs::File::open(path).with_context(|| format!("opening {}", path.display()))?;
    serde_json::from_reader(file).with_context(|| format!("parsing {}", path.display()))
}

fn boot_version(assets_lock: &str) -> Result<String> {
    let lock: toml::Table = assets_lock.parse().context("parsing assets.lock")?;
    lock.get("boot")
        .and_then(|boot| boot.get("version"))
        .and_then(toml::Value::as_str)
        .map(str::to_owned)
        .context("assets.lock has no [boot] version")
}

/// One key per third-party artifact the bundle ships or the runtime pins:
/// `tool:<name>@<version>` for each third-party `assets.lock` tool,
/// `qemu:qemu@<version>` for the QEMU build the daemon downloads on a Mac
/// without hardware virtualization, `boot:kernel@<kernel ref>` and
/// `boot:rootfs@<boot-assets version>`, and `runtime:<name>@<version>` for
/// each boot-manifest binary with a host target.
fn shipped_keys(assets_lock: &str, manifest: &Value) -> Result<BTreeSet<String>> {
    let lock: toml::Table = assets_lock.parse().context("parsing assets.lock")?;
    let mut keys = BTreeSet::new();
    // An empty sha256 pins no build: the daemon downloads nothing.
    if let Some(qemu) = lock.get("qemu") {
        let sha256 = qemu
            .get("arch")
            .and_then(|arch| arch.get(HOST_ARCH))
            .and_then(|arch| arch.get("sha256"))
            .and_then(toml::Value::as_str)
            .unwrap_or_default();
        if !sha256.is_empty() {
            let version = qemu
                .get("version")
                .and_then(toml::Value::as_str)
                .context("assets.lock [qemu] pins a build but has no version")?;
            keys.insert(format!("qemu:qemu@{version}"));
        }
    }
    for tool in lock
        .get("tools")
        .and_then(toml::Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default()
    {
        let field = |name: &str| {
            tool.get(name)
                .and_then(toml::Value::as_str)
                .with_context(|| format!("assets.lock tool is missing `{name}`"))
        };
        keys.insert(format!("tool:{}@{}", field("name")?, field("version")?));
    }

    let target = &manifest["targets"][HOST_ARCH];
    let kernel = target["kernel"]["version"]
        .as_str()
        .context("boot manifest has no kernel version for the host target")?;
    keys.insert(format!("boot:kernel@{kernel}"));
    let rootfs = manifest["asset_version"]
        .as_str()
        .context("boot manifest has no asset_version")?;
    keys.insert(format!("boot:rootfs@{rootfs}"));

    for binary in manifest["binaries"]
        .as_array()
        .context("boot manifest binaries must be an array")?
    {
        if binary["targets"][HOST_ARCH].is_null() {
            continue;
        }
        let name = binary["name"]
            .as_str()
            .context("boot manifest binary has no name")?;
        let version = binary["version"]
            .as_str()
            .with_context(|| format!("boot manifest binary {name} has no version"))?;
        keys.insert(format!("runtime:{name}@{version}"));
    }
    Ok(keys)
}

fn covered_keys(components: &Value) -> BTreeSet<String> {
    components["groups"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|group| group["covers"].as_array().into_iter().flatten())
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect()
}

/// The notices must describe exactly what ships: a new or re-versioned
/// artifact needs its license and source reviewed, and an entry for an
/// artifact that no longer ships would misstate what the bundle contains.
fn check_coverage(shipped: &BTreeSet<String>, covered: &BTreeSet<String>) -> Result<()> {
    let missing: Vec<_> = shipped.difference(covered).cloned().collect();
    let stale: Vec<_> = covered.difference(shipped).cloned().collect();
    if missing.is_empty() && stale.is_empty() {
        println!(
            "  components.json covers all {} shipped artifacts",
            shipped.len()
        );
        return Ok(());
    }
    let mut message = String::from(
        "ThirdPartyNotices/components.json does not match what this bundle ships. \
         Update the group that covers each artifact: its version, license, source \
         and license files, then its `covers` key.",
    );
    if !missing.is_empty() {
        message.push_str(&format!(
            "\n  shipped but not covered: {}",
            missing.join(", ")
        ));
    }
    if !stale.is_empty() {
        message.push_str(&format!(
            "\n  covered but not shipped: {}",
            stale.join(", ")
        ));
    }
    bail!(message)
}

/// Copies each pinned package's top-level license and notice files into
/// `notices/swift-packages/<identity>/` and describes the package for
/// `generated.json`.
fn collect_swift_packages(
    resolved: &Value,
    checkouts: &Path,
    notices: &Path,
) -> Result<Vec<Value>> {
    let mut packages = Vec::new();
    for pin in resolved["pins"]
        .as_array()
        .context("Package.resolved has no pins")?
    {
        let identity = pin["identity"].as_str().context("pin has no identity")?;
        let location = pin["location"]
            .as_str()
            .with_context(|| format!("pin {identity} has no location"))?;
        let repository = location.trim_end_matches('/').trim_end_matches(".git");
        let name = repository.rsplit('/').next().unwrap_or(identity);
        let version = pin["state"]["version"]
            .as_str()
            .or_else(|| pin["state"]["revision"].as_str())
            .with_context(|| format!("pin {identity} has no version or revision"))?;

        let checkout = checkouts.join(name);
        let files = license_files(&checkout)?;
        if files.is_empty() {
            bail!(
                "Swift package {identity} has no LICENSE, COPYING or NOTICE file in {}",
                checkout.display()
            );
        }
        let dest = notices.join("swift-packages").join(identity);
        std::fs::create_dir_all(&dest)?;
        let mut license = "See license text";
        let mut paths = Vec::new();
        for file in &files {
            std::fs::copy(checkout.join(file), dest.join(file))
                .with_context(|| format!("copying {identity}/{file}"))?;
            if license == "See license text" && !file.to_ascii_uppercase().starts_with("NOTICE") {
                license = classify_license(&std::fs::read_to_string(checkout.join(file))?);
            }
            paths.push(format!("swift-packages/{identity}/{file}"));
        }
        packages.push(json!({
            "name": name,
            "version": version,
            "license": license,
            "source": repository,
            "licenseFiles": paths,
        }));
    }
    Ok(packages)
}

/// Top-level license and notice files, sorted so LICENSE comes before NOTICE.
fn license_files(checkout: &Path) -> Result<Vec<String>> {
    let mut files = Vec::new();
    for entry in std::fs::read_dir(checkout)
        .with_context(|| format!("reading Swift package checkout {}", checkout.display()))?
    {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let upper = name.to_ascii_uppercase();
        if entry.file_type()?.is_file()
            && ["LICENSE", "LICENCE", "COPYING", "NOTICE"]
                .iter()
                .any(|prefix| upper.starts_with(prefix))
        {
            files.push(name);
        }
    }
    files.sort_by_key(|name| {
        (
            name.to_ascii_uppercase().starts_with("NOTICE"),
            name.clone(),
        )
    });
    Ok(files)
}

/// A short label for the list; the license text itself is what the app shows.
/// Files that append third-party terms (PLCrashReporter: MIT, then Apache-2.0
/// for some sources) are labelled by the license they open with.
fn classify_license(text: &str) -> &'static str {
    const MARKERS: [(&str, &str); 4] = [
        ("Apache License", "Apache-2.0"),
        ("Permission is hereby granted, free of charge", "MIT"),
        ("Redistribution and use in source and binary forms", "BSD"),
        ("Permission to use, copy, modify, and/or distribute", "ISC"),
    ];
    match MARKERS
        .iter()
        .filter_map(|(marker, label)| text.find(marker).map(|at| (at, *label)))
        .min()
    {
        Some((_, "BSD")) if text.contains("Neither the name") => "BSD-3-Clause",
        Some((_, "BSD")) => "BSD-2-Clause",
        Some((_, label)) => label,
        None => "See license text",
    }
}

/// The SPDX ids in cargo-about's overview, in its order (most crates first):
/// `- [MIT License](#MIT) (627 crates)`.
fn cargo_about_licenses(notice: &str) -> Vec<String> {
    let overview = notice.split("## License Texts").next().unwrap_or_default();
    let pattern = regex::Regex::new(r"(?m)^- \[[^\]]+\]\(#([^)]+)\)").expect("valid regex");
    pattern
        .captures_iter(overview)
        .map(|captures| captures[1].to_owned())
        .collect()
}
