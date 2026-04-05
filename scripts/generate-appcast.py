#!/usr/bin/env python3
"""
Generate or update a Sparkle 2.x appcast XML feed for ArcBox.

Creates a new appcast RSS document, or merges a new release item into an
existing one (removing duplicate versions and legacy stable channel tags).

Usage:
    generate-appcast.py --version 1.2.0 --build-number 42 \
        --dmg-url https://example.com/ArcBox-1.2.0.dmg \
        --dmg-length 12345678 --ed-signature "abc..." \
        --output appcast.xml

    generate-appcast.py --version 1.3.0-beta.1 --build-number 43 \
        --dmg-url https://example.com/ArcBox-1.3.0-beta.1.dmg \
        --dmg-length 12345679 --ed-signature "def..." \
        --channel beta --existing appcast.xml --output appcast.xml
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime, timezone
from email.utils import formatdate
from pathlib import Path


def rfc2822_now() -> str:
    """Return the current UTC time in RFC 2822 format."""
    return formatdate(timeval=datetime.now(timezone.utc).timestamp(), usegmt=True)


def build_item(
    display_version: str,
    build_number: str,
    dmg_url: str,
    dmg_length: str,
    ed_signature: str,
    channel: str,
    min_macos: str,
    pub_date: str,
) -> str:
    """Build a single <item> XML fragment."""
    channel_element = ""
    if channel != "stable":
        channel_element = f"\n        <sparkle:channel>{channel}</sparkle:channel>"

    return (
        f"      <item>\n"
        f"        <title>ArcBox {display_version}</title>\n"
        f"        <pubDate>{pub_date}</pubDate>\n"
        f"        <sparkle:version>{build_number}</sparkle:version>\n"
        f"        <sparkle:shortVersionString>{display_version}</sparkle:shortVersionString>"
        f"{channel_element}\n"
        f"        <sparkle:minimumSystemVersion>{min_macos}</sparkle:minimumSystemVersion>\n"
        f"        <enclosure\n"
        f'          url="{dmg_url}"\n'
        f'          length="{dmg_length}"\n'
        f'          type="application/octet-stream"\n'
        f'          sparkle:edSignature="{ed_signature}"\n'
        f"        />\n"
        f"      </item>"
    )


def new_appcast(item: str) -> str:
    """Return a complete appcast RSS document containing a single item."""
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n'
        "  <channel>\n"
        "    <title>ArcBox</title>\n"
        "    <link>https://arcbox.dev</link>\n"
        "    <description>ArcBox release feed</description>\n"
        "    <language>en</language>\n"
        f"{item}\n"
        "    </channel>\n"
        "  </rss>\n"
    )


def merge_appcast(existing_path: Path, item: str, display_version: str) -> str:
    """Merge a new item into an existing appcast, removing duplicates."""
    content = existing_path.read_text()

    # Remove any existing items that match this version by shortVersionString
    # or sparkle:version (build number is the display_version for dedup).
    for tag in ("sparkle:shortVersionString", "sparkle:version"):
        pattern = (
            r"\s*<item>.*?<"
            + tag
            + r">"
            + re.escape(display_version)
            + r"</"
            + tag
            + r">.*?</item>"
        )
        content = re.sub(pattern, "", content, flags=re.DOTALL)

    # Strip legacy <sparkle:channel>stable</sparkle:channel> tags.
    content = re.sub(r"\n\s*<sparkle:channel>stable</sparkle:channel>", "", content)

    # Insert the new item right before </channel>.
    content = content.replace("    </channel>", item + "\n    </channel>")

    return content


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate or update a Sparkle 2.x appcast for ArcBox.",
    )
    parser.add_argument("--version", required=True, help="Release version (e.g. v1.2.0)")
    parser.add_argument("--build-number", required=True, help="CFBundleVersion build number")
    parser.add_argument("--dmg-url", required=True, help="Download URL for the DMG")
    parser.add_argument("--dmg-length", required=True, help="DMG file size in bytes")
    parser.add_argument("--ed-signature", required=True, help="EdDSA (ed25519) signature")
    parser.add_argument("--channel", default="stable", help="Sparkle channel (default: stable)")
    parser.add_argument("--min-macos", default="15.0", help="Minimum macOS version (default: 15.0)")
    parser.add_argument("--output", required=True, type=Path, help="Output appcast XML path")
    parser.add_argument("--existing", default=None, type=Path, help="Existing appcast to merge into")

    args = parser.parse_args()

    display_version = args.version.lstrip("v")
    pub_date = rfc2822_now()

    item = build_item(
        display_version=display_version,
        build_number=args.build_number,
        dmg_url=args.dmg_url,
        dmg_length=args.dmg_length,
        ed_signature=args.ed_signature,
        channel=args.channel,
        min_macos=args.min_macos,
        pub_date=pub_date,
    )

    if args.existing and args.existing.is_file():
        print(f"Merging into existing appcast: {args.existing}")
        content = merge_appcast(args.existing, item, display_version)
        args.output.write_text(content)
        print(f"Updated appcast with version {display_version}")
    else:
        print("Creating new appcast")
        content = new_appcast(item)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
        print(f"Created new appcast with version {display_version}")

    print(f"Output: {args.output}")


if __name__ == "__main__":
    main()
