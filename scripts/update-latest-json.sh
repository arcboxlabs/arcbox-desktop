#!/bin/bash
# Maintain a latest.json file tracking the latest version per channel.
#
# Usage:
#   scripts/update-latest-json.sh \
#     --version v1.2.0 \
#     --channel stable \
#     --output latest.json \
#     [--existing existing-latest.json]
#
# Output format:
#   {"stable":{"version":"1.2.0","date":"2026-03-09T12:00:00Z"},...}

set -euo pipefail

VERSION="" CHANNEL="stable" OUTPUT="" EXISTING=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)  VERSION="$2";  shift 2 ;;
        --channel)  CHANNEL="$2";  shift 2 ;;
        --output)   OUTPUT="$2";   shift 2 ;;
        --existing) EXISTING="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for var in VERSION CHANNEL OUTPUT; do
    if [ -z "${!var}" ]; then
        echo "error: --$(echo "$var" | tr '[:upper:]' '[:lower:]') is required" >&2
        exit 1
    fi
done

DISPLAY_VERSION="${VERSION#v}"
ISO_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

python3 -c "
import json, sys

existing = {}
existing_path = '$EXISTING'
if existing_path:
    try:
        with open(existing_path, 'r') as f:
            existing = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

existing['$CHANNEL'] = {
    'version': '$DISPLAY_VERSION',
    'date': '$ISO_DATE'
}

with open('$OUTPUT', 'w') as f:
    json.dump(existing, f, indent=2, sort_keys=True)
    f.write('\n')
"

echo "Updated latest.json: channel=$CHANNEL version=$DISPLAY_VERSION"
echo "Output: $OUTPUT"
