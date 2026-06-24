//! Generate or update a Sparkle 2.x appcast XML feed for ArcBox.
//!
//! Ported from the former `generate-appcast.py`. The output is byte-for-byte
//! compatible with the previous Python implementation, including the embedded
//! release-notes `<description>` CDATA path and the regex-based merge that
//! de-duplicates versions in an existing feed.
//!
//! This is intentionally implemented locally rather than via
//! `xtask_kit::sparkle`, which has no field for an embedded release-notes
//! description (the `--release-notes-html` feature CI relies on).

use anyhow::{Context, Result};
use regex::Regex;
use time::OffsetDateTime;
use time::macros::format_description;

use crate::ReleaseAppcastArgs;

/// Current UTC time in RFC 2822 form with a literal `GMT` zone, matching
/// Python's `email.utils.formatdate(usegmt=True)`.
fn rfc2822_now() -> Result<String> {
    let format = format_description!(
        "[weekday repr:short], [day] [month repr:short] [year] [hour]:[minute]:[second] GMT"
    );
    OffsetDateTime::now_utc()
        .format(&format)
        .context("formatting pubDate")
}

/// Wrap text in a CDATA section, splitting any `]]>` terminators.
fn cdata(text: &str) -> String {
    format!("<![CDATA[{}]]>", text.replace("]]>", "]]]]><![CDATA[>"))
}

fn build_item(
    args: &ReleaseAppcastArgs,
    display_version: &str,
    pub_date: &str,
    release_notes_html: Option<&str>,
) -> String {
    let channel_element = if args.channel != "stable" {
        format!(
            "\n        <sparkle:channel>{}</sparkle:channel>",
            args.channel
        )
    } else {
        String::new()
    };

    // Embedded HTML renders inside Sparkle's update dialog; a releaseNotesLink
    // is the fallback when no notes are supplied.
    let notes_element = match release_notes_html {
        Some(html) => format!("        <description>{}</description>", cdata(html)),
        None => format!(
            "        <sparkle:releaseNotesLink>https://github.com/arcboxlabs/arcbox-desktop/releases/tag/v{display_version}</sparkle:releaseNotesLink>"
        ),
    };

    let mut item = String::new();
    item.push_str("      <item>\n");
    item.push_str(&format!(
        "        <title>ArcBox {display_version}</title>\n"
    ));
    item.push_str(&notes_element);
    item.push('\n');
    item.push_str(&format!("        <pubDate>{pub_date}</pubDate>\n"));
    item.push_str(&format!(
        "        <sparkle:version>{}</sparkle:version>\n",
        args.build_number
    ));
    item.push_str(&format!(
        "        <sparkle:shortVersionString>{display_version}</sparkle:shortVersionString>"
    ));
    item.push_str(&channel_element);
    item.push('\n');
    item.push_str(&format!(
        "        <sparkle:minimumSystemVersion>{}</sparkle:minimumSystemVersion>\n",
        args.min_macos
    ));
    item.push_str("        <enclosure\n");
    item.push_str(&format!("          url=\"{}\"\n", args.dmg_url));
    item.push_str(&format!("          length=\"{}\"\n", args.dmg_length));
    item.push_str("          type=\"application/octet-stream\"\n");
    item.push_str(&format!(
        "          sparkle:edSignature=\"{}\"\n",
        args.ed_signature
    ));
    item.push_str("        />\n");
    item.push_str("      </item>");
    item
}

fn new_appcast(item: &str) -> String {
    format!(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n\
         <rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\">\n\
         \x20 <channel>\n\
         \x20   <title>ArcBox</title>\n\
         \x20   <link>https://arcbox.dev</link>\n\
         \x20   <description>ArcBox release feed</description>\n\
         \x20   <language>en</language>\n\
         {item}\n\
         \x20   </channel>\n\
         \x20 </rss>\n"
    )
}

fn merge_appcast(existing: &str, item: &str, display_version: &str) -> Result<String> {
    // Drop any existing <item> matching this version by shortVersionString or
    // sparkle:version. Each item is matched individually (non-greedy) so a
    // single match never swallows preceding items.
    let item_re = Regex::new(r"(?s)\s*<item>.*?</item>").context("compiling item regex")?;
    let merged = item_re.replace_all(existing, |caps: &regex::Captures<'_>| {
        let item_xml = &caps[0];
        for tag in ["sparkle:shortVersionString", "sparkle:version"] {
            if item_xml.contains(&format!("<{tag}>{display_version}</{tag}>")) {
                return String::new();
            }
        }
        item_xml.to_string()
    });

    // Strip legacy <sparkle:channel>stable</sparkle:channel> tags.
    let channel_re = Regex::new(r"\n\s*<sparkle:channel>stable</sparkle:channel>")
        .context("compiling channel regex")?;
    let stripped = channel_re.replace_all(&merged, "");

    // Insert the new item right before </channel>.
    Ok(stripped.replace("    </channel>", &format!("{item}\n    </channel>")))
}

pub fn run(args: ReleaseAppcastArgs) -> Result<()> {
    let display_version = args.version.trim_start_matches('v').to_string();
    let pub_date = rfc2822_now()?;

    let release_notes_html = match &args.release_notes_html {
        Some(path) if path.is_file() => {
            let raw = std::fs::read_to_string(path)
                .with_context(|| format!("reading {}", path.display()))?;
            let trimmed = raw.trim().to_string();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed)
            }
        }
        _ => None,
    };

    let item = build_item(
        &args,
        &display_version,
        &pub_date,
        release_notes_html.as_deref(),
    );

    if let Some(parent) = args.output.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating {}", parent.display()))?;
    }

    let content = match &args.existing {
        Some(existing) if existing.is_file() => {
            println!("Merging into existing appcast: {}", existing.display());
            let existing_content = std::fs::read_to_string(existing)
                .with_context(|| format!("reading {}", existing.display()))?;
            let merged = merge_appcast(&existing_content, &item, &display_version)?;
            println!("Updated appcast with version {display_version}");
            merged
        }
        _ => {
            println!("Creating new appcast");
            let created = new_appcast(&item);
            println!("Created new appcast with version {display_version}");
            created
        }
    };

    std::fs::write(&args.output, content)
        .with_context(|| format!("writing {}", args.output.display()))?;
    println!("Output: {}", args.output.display());
    Ok(())
}
