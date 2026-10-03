//! Build the release notes Sparkle renders, from a release's changelog entry.
//!
//! Notes are the curated `### Highlights` prose *and* the release's
//! user-facing sections, in that order — the prose says why to update, the
//! sections say what changed. Either may be absent; only a release with
//! neither has nothing to tell anyone, and that is the one case worth
//! refusing to build.

use anyhow::{Context, Result, bail};

use crate::ReleaseNotesArgs;

/// The sections a user is meant to read, matching `ChangelogParser`'s own set
/// so the About window and the update dialog never disagree about what counts
/// as user-facing. Everything else release-please files — Miscellaneous, CI,
/// Refactoring, Documentation — is internal bookkeeping.
const USER_FACING_SECTIONS: [&str; 4] = ["Features", "Bug Fixes", "Performance", "Security"];

struct Section {
    title: String,
    items: Vec<String>,
}

fn changelog_version(line: &str) -> Option<&str> {
    let rest = line.trim().strip_prefix("## [")?;
    Some(&rest[..rest.find(']')?])
}

/// Drop the `([#123](url))` and `([abc1234](url))` trailers release-please
/// appends. They point at issues and commits, which is the right reference for
/// a changelog and pure noise in an update dialog.
fn strip_trailing_links(item: &str) -> String {
    let mut out = item.trim_end();
    while out.ends_with(')') {
        let Some(start) = out.rfind(" ([") else { break };
        // A single `](` marks one well-formed link; anything else is prose we
        // have no business rewriting.
        if out[start..].matches("](").count() != 1 {
            break;
        }
        out = out[..start].trim_end();
    }
    out.to_string()
}

fn extract(changelog: &str, version: &str) -> Result<(String, Vec<Section>)> {
    let wanted = version.trim_start_matches('v');
    let mut found_release = false;
    let mut in_release = false;
    let mut highlights = Vec::new();
    let mut sections: Vec<Section> = Vec::new();
    let mut current: Option<&str> = None;

    for line in changelog.lines() {
        if let Some(candidate) = changelog_version(line) {
            if in_release {
                break;
            }
            in_release = candidate == wanted;
            found_release |= in_release;
            continue;
        }
        if !in_release {
            continue;
        }

        let trimmed = line.trim();
        if let Some(title) = trimmed.strip_prefix("### ") {
            current = match title {
                "Highlights" => Some("Highlights"),
                title if USER_FACING_SECTIONS.contains(&title) => {
                    sections.push(Section {
                        title: title.to_string(),
                        items: Vec::new(),
                    });
                    Some("section")
                }
                _ => None,
            };
            continue;
        }

        match current {
            Some("Highlights") => highlights.push(line),
            Some(_) if trimmed.starts_with("* ") => {
                if let Some(section) = sections.last_mut() {
                    section.items.push(strip_trailing_links(trimmed));
                }
            }
            _ => {}
        }
    }

    if !found_release {
        bail!("release {wanted} is missing from the changelog");
    }

    let highlights = highlights.join("\n").trim().to_string();
    sections.retain(|section| !section.items.is_empty());
    if highlights.is_empty() && sections.is_empty() {
        bail!(
            "release {wanted} has nothing to show users: no ### Highlights, and no entries under {}",
            USER_FACING_SECTIONS.join(" / ")
        );
    }

    Ok((highlights, sections))
}

fn render(highlights: &str, sections: &[Section]) -> String {
    let mut blocks = Vec::new();
    if !highlights.is_empty() {
        blocks.push(highlights.to_string());
    }
    for section in sections {
        blocks.push(format!(
            "### {}\n\n{}",
            section.title,
            section.items.join("\n")
        ));
    }
    blocks.join("\n\n")
}

pub fn run(args: ReleaseNotesArgs) -> Result<()> {
    let changelog = std::fs::read_to_string(&args.changelog)
        .with_context(|| format!("reading {}", args.changelog.display()))?;
    let (highlights, sections) = extract(&changelog, &args.version)?;
    let notes = render(&highlights, &sections);

    if let Some(parent) = args
        .output
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating {}", parent.display()))?;
    }
    std::fs::write(&args.output, format!("{notes}\n"))
        .with_context(|| format!("writing {}", args.output.display()))?;
    println!("Release notes: {}", args.output.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const CHANGELOG: &str = r#"
# Changelog

## [1.2.0](https://example.com) (2026-08-10)

### Highlights

**Faster startup.** ArcBox now reports each startup phase.

### Features

* **sandboxes:** surface the template catalog ([#387](https://example.com/387)) ([abc1234](https://example.com/abc1234))

### Miscellaneous

* bump arcbox version to v0.6.6 ([#391](https://example.com/391))

## [1.1.0](https://example.com) (2026-08-01)

### Highlights

Older notes.
"#;

    fn notes(changelog: &str, version: &str) -> Result<String> {
        let (highlights, sections) = extract(changelog, version)?;
        Ok(render(&highlights, &sections))
    }

    #[test]
    fn pairs_highlights_with_the_user_facing_sections() {
        assert_eq!(
            notes(CHANGELOG, "v1.2.0").unwrap(),
            "**Faster startup.** ArcBox now reports each startup phase.\n\n\
             ### Features\n\n\
             * **sandboxes:** surface the template catalog"
        );
    }

    #[test]
    fn falls_back_to_the_sections_when_highlights_are_absent() {
        let changelog = r#"
## [1.2.0] (2026-08-10)

### Bug Fixes

* **ui:** slide the detail tab indicator ([#386](https://example.com/386)) ([def5678](https://example.com/def5678))
"#;
        assert_eq!(
            notes(changelog, "1.2.0").unwrap(),
            "### Bug Fixes\n\n* **ui:** slide the detail tab indicator"
        );
    }

    #[test]
    fn rejects_a_release_with_nothing_user_facing() {
        // A bare engine bump: release-please files it under Miscellaneous, so
        // only a human can say what it means for anyone.
        let changelog = r#"
## [1.36.1] (2026-08-13)

### Miscellaneous

* bump arcbox version to v0.6.6 ([#391](https://example.com/391))
"#;
        assert!(
            notes(changelog, "1.36.1")
                .unwrap_err()
                .to_string()
                .contains("nothing to show users")
        );
    }

    #[test]
    fn rejects_a_release_that_is_not_in_the_changelog() {
        assert!(notes(CHANGELOG, "9.9.9").is_err());
    }

    #[test]
    fn strips_only_well_formed_trailers() {
        assert_eq!(
            strip_trailing_links(
                "* **ui:** fix ([#1](https://e.com/1)) ([abc](https://e.com/abc))"
            ),
            "* **ui:** fix"
        );
        assert_eq!(
            strip_trailing_links("* keep prose (like this) intact"),
            "* keep prose (like this) intact"
        );
    }
}
