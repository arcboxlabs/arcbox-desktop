#!/usr/bin/env python3
"""
Update (or create) the latest.json manifest used by Sparkle for update checks.

Reads an optional existing JSON file, merges in the new channel entry, and
writes the result.  The version string is stripped of a leading "v" and an
ISO 8601 UTC timestamp is added automatically.

Usage:
    update-latest-json.py --version 1.2.0 --channel stable --output latest.json
    update-latest-json.py --version v1.3.0-beta.1 --channel beta --output latest.json \
        --existing latest.json
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def update_latest_json(
    version: str,
    channel: str,
    output: Path,
    existing: Path | None = None,
) -> None:
    """Build the latest.json content and write it to *output*."""
    data: dict[str, object] = {}

    if existing and existing.is_file():
        print(f"  Loading existing file: {existing}")
        try:
            data = json.loads(existing.read_text())
        except (json.JSONDecodeError, OSError) as exc:
            print(f"  Warning: could not load existing file ({exc}), starting fresh")

    display_version = version.lstrip("v")
    iso_date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    data[channel] = {
        "version": display_version,
        "date": iso_date,
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"  Updated latest.json: channel={channel} version={display_version}")
    print(f"  Output: {output}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Update the latest.json manifest with a new channel entry.",
    )
    parser.add_argument(
        "--version",
        required=True,
        help='Release version (leading "v" is stripped automatically)',
    )
    parser.add_argument(
        "--channel",
        default="stable",
        help="Update channel name (default: stable)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Path to write the resulting latest.json",
    )
    parser.add_argument(
        "--existing",
        type=Path,
        default=None,
        help="Path to an existing latest.json to merge into",
    )

    args = parser.parse_args()

    update_latest_json(
        version=args.version,
        channel=args.channel,
        output=args.output,
        existing=args.existing,
    )


if __name__ == "__main__":
    main()
