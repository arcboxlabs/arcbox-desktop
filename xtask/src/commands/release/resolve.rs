//! `release resolve` — derive the build version, Sparkle channel, prerelease
//! flag, and arcbox source ref, and write them to `GITHUB_OUTPUT`.
//!
//! Consolidates the former "Resolve arcbox ref" and "Determine version" shell
//! steps. The brittle parts (MARKETING_VERSION parsing, channel detection,
//! prerelease regex) are pure functions covered by unit tests below.

use anyhow::Result;
use xtask_kit::{github_actions, repo};

use crate::ReleaseResolveArgs;

/// Extract `MARKETING_VERSION` from Version.xcconfig text, stripping any
/// trailing `// comment`. Mirrors the previous `sed`/`tr` pipeline.
fn parse_marketing_version(xcconfig: &str) -> Option<String> {
    xcconfig.lines().find_map(|line| {
        let rest = line.strip_prefix("MARKETING_VERSION")?.trim_start();
        let rest = rest.strip_prefix('=')?;
        let value = rest.split("//").next().unwrap_or("").trim();
        (!value.is_empty()).then(|| value.to_string())
    })
}

/// A version is a prerelease when it carries an alpha/beta/rc qualifier.
fn is_prerelease(version: &str) -> bool {
    ["alpha", "beta", "rc"]
        .iter()
        .any(|kind| version.contains(kind))
}

/// Map a version string to its Sparkle update channel.
fn channel_for(version: &str) -> &'static str {
    if version.contains("alpha") {
        "alpha"
    } else if version.contains("beta") {
        "beta"
    } else if version.contains("rc") {
        "rc"
    } else {
        "stable"
    }
}

/// Determine the release version from the trigger context.
fn compute_version(
    event_name: &str,
    tag: &str,
    xcconfig_version: &str,
    github_ref: &str,
) -> String {
    if event_name == "workflow_dispatch" {
        if tag.is_empty() {
            format!("v{xcconfig_version}")
        } else {
            tag.to_string()
        }
    } else {
        github_ref
            .strip_prefix("refs/tags/")
            .unwrap_or(github_ref)
            .to_string()
    }
}

/// Resolve the arcbox source ref: explicit input wins, then arcbox.version,
/// then "master". `arcbox_version` is the file contents when it exists.
fn compute_ref(arcbox_ref: &str, arcbox_version: Option<&str>) -> String {
    if !arcbox_ref.is_empty() && arcbox_ref != "master" {
        arcbox_ref.to_string()
    } else if let Some(contents) = arcbox_version {
        // `tr -d '[:space:]'`: drop all whitespace.
        contents.split_whitespace().collect()
    } else {
        "master".to_string()
    }
}

pub fn run(args: ReleaseResolveArgs) -> Result<()> {
    let root = repo::root_from_xtask_manifest(env!("CARGO_MANIFEST_DIR"))?;

    let xcconfig = std::fs::read_to_string(root.join("Version.xcconfig")).unwrap_or_default();
    let xcconfig_version = parse_marketing_version(&xcconfig).unwrap_or_default();

    let arcbox_version = std::fs::read_to_string(root.join("arcbox.version")).ok();
    let arcbox_ref = compute_ref(&args.arcbox_ref, arcbox_version.as_deref());

    let version = compute_version(
        &args.event_name,
        &args.tag,
        &xcconfig_version,
        &args.github_ref,
    );
    let channel = channel_for(&version);
    let prerelease = is_prerelease(&version);

    println!("Arcbox ref: {arcbox_ref}");
    println!("Building version: {version}");

    let tag_version = version.trim_start_matches('v');
    if tag_version != xcconfig_version {
        println!(
            "::warning::Tag version ({tag_version}) differs from Version.xcconfig ({xcconfig_version})"
        );
    }

    github_actions::append_output_env("ref", &arcbox_ref)?;
    github_actions::append_output_env("version", &version)?;
    github_actions::append_output_env("prerelease", if prerelease { "true" } else { "false" })?;
    github_actions::append_output_env("channel", channel)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_marketing_version() {
        assert_eq!(
            parse_marketing_version("MARKETING_VERSION = 1.22.9 // x-release-please-version")
                .as_deref(),
            Some("1.22.9")
        );
        assert_eq!(
            parse_marketing_version("MARKETING_VERSION=2.0.0").as_deref(),
            Some("2.0.0")
        );
        assert_eq!(
            parse_marketing_version("CURRENT_PROJECT_VERSION = 1\nMARKETING_VERSION = 3.1.4\n")
                .as_deref(),
            Some("3.1.4")
        );
        assert_eq!(parse_marketing_version("MARKETING_VERSION_EXTRA = 9"), None);
        assert_eq!(parse_marketing_version("# nothing here"), None);
    }

    #[test]
    fn detects_channel_and_prerelease() {
        assert_eq!(channel_for("v1.2.0"), "stable");
        assert_eq!(channel_for("v1.3.0-alpha.1"), "alpha");
        assert_eq!(channel_for("v1.3.0-beta.2"), "beta");
        assert_eq!(channel_for("v1.3.0-rc.1"), "rc");
        assert!(!is_prerelease("v1.2.0"));
        assert!(is_prerelease("v1.3.0-beta.1"));
        assert!(is_prerelease("v1.3.0-rc.2"));
    }

    #[test]
    fn computes_version() {
        assert_eq!(
            compute_version("workflow_dispatch", "v9.9.9", "1.2.3", ""),
            "v9.9.9"
        );
        assert_eq!(
            compute_version("workflow_dispatch", "", "1.2.3", ""),
            "v1.2.3"
        );
        assert_eq!(
            compute_version("push", "", "1.2.3", "refs/tags/v1.2.3"),
            "v1.2.3"
        );
    }

    #[test]
    fn computes_ref() {
        assert_eq!(compute_ref("feature-x", None), "feature-x");
        assert_eq!(compute_ref("master", Some("v0.4.10\n")), "v0.4.10");
        assert_eq!(compute_ref("", Some("  v0.4.10 \n")), "v0.4.10");
        assert_eq!(compute_ref("", None), "master");
    }
}
