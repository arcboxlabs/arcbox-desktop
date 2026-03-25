#!/bin/bash
# Generate or update a Sparkle appcast XML file.
#
# Usage:
#   scripts/generate-appcast.sh \
#     --version v1.2.0 \
#     --dmg-url https://release.arcboxcdn.com/desktop/v1.2.0/ArcBox-arm64.dmg \
#     --dmg-length 12345678 \
#     --ed-signature "base64sig==" \
#     --channel stable \
#     --min-macos 15.0 \
#     --output appcast.xml \
#     [--existing existing-appcast.xml]
#
# If --existing is provided and the file exists, the new <item> is inserted
# before </channel>. If the same version already exists, it is replaced.
# Otherwise a complete RSS document is created from scratch.

set -euo pipefail

# Parse arguments
VERSION="" DMG_URL="" DMG_LENGTH="" ED_SIGNATURE="" CHANNEL="stable"
MIN_MACOS="15.0" OUTPUT="" EXISTING=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)      VERSION="$2";      shift 2 ;;
        --dmg-url)      DMG_URL="$2";      shift 2 ;;
        --dmg-length)   DMG_LENGTH="$2";   shift 2 ;;
        --ed-signature) ED_SIGNATURE="$2"; shift 2 ;;
        --channel)      CHANNEL="$2";      shift 2 ;;
        --min-macos)    MIN_MACOS="$2";    shift 2 ;;
        --output)       OUTPUT="$2";       shift 2 ;;
        --existing)     EXISTING="$2";     shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for var in VERSION DMG_URL DMG_LENGTH ED_SIGNATURE OUTPUT; do
    if [ -z "${!var}" ]; then
        echo "error: --$(echo "$var" | tr '[:upper:]' '[:lower:]' | tr '_' '-') is required" >&2
        exit 1
    fi
done

# Strip leading "v" for display version
DISPLAY_VERSION="${VERSION#v}"

# BSD/GNU-compatible UTC date
PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')

# Build the <item> block
ITEM=$(cat <<ITEM_EOF
      <item>
        <title>ArcBox $DISPLAY_VERSION</title>
        <pubDate>$PUB_DATE</pubDate>
        <sparkle:version>$DISPLAY_VERSION</sparkle:version>
        <sparkle:channel>$CHANNEL</sparkle:channel>
        <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
        <enclosure
          url="$DMG_URL"
          length="$DMG_LENGTH"
          type="application/octet-stream"
          sparkle:edSignature="$ED_SIGNATURE"
        />
      </item>
ITEM_EOF
)

# If we have an existing appcast, merge into it
if [ -n "$EXISTING" ] && [ -f "$EXISTING" ]; then
    echo "Merging into existing appcast: $EXISTING"

    # Remove existing item with the same sparkle:version (if any)
    # Use python3 for reliable XML-like text manipulation
    python3 -c "
import sys, re

with open('$EXISTING', 'r') as f:
    content = f.read()

version = '$DISPLAY_VERSION'
item = '''$ITEM'''

# Remove existing item block for the same version
pattern = r'\s*<item>.*?<sparkle:version>' + re.escape(version) + r'</sparkle:version>.*?</item>'
content = re.sub(pattern, '', content, flags=re.DOTALL)

# Insert new item before </channel>
content = content.replace('    </channel>', item + '\n    </channel>')

with open('$OUTPUT', 'w') as f:
    f.write(content)
"
    echo "Updated appcast with version $DISPLAY_VERSION"
else
    echo "Creating new appcast"

    cat > "$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ArcBox</title>
    <link>https://arcbox.dev</link>
    <description>ArcBox release feed</description>
    <language>en</language>
$ITEM
    </channel>
  </rss>
EOF
    echo "Created new appcast with version $DISPLAY_VERSION"
fi

echo "Output: $OUTPUT"
