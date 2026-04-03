#!/bin/bash
# Generate or update a Sparkle appcast XML file.
#
# Usage:
#   scripts/generate-appcast.sh \
#     --version v1.2.0 \
#     --build-number 501 \
#     --dmg-url https://release.arcboxcdn.com/desktop/v1.2.0/ArcBox-1.2.0-arm64.dmg \
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
MIN_MACOS="15.0" OUTPUT="" EXISTING="" BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)       VERSION="$2";       shift 2 ;;
        --build-number)  BUILD_NUMBER="$2";  shift 2 ;;
        --dmg-url)       DMG_URL="$2";       shift 2 ;;
        --dmg-length)    DMG_LENGTH="$2";    shift 2 ;;
        --ed-signature)  ED_SIGNATURE="$2";  shift 2 ;;
        --channel)       CHANNEL="$2";       shift 2 ;;
        --min-macos)     MIN_MACOS="$2";     shift 2 ;;
        --output)        OUTPUT="$2";        shift 2 ;;
        --existing)      EXISTING="$2";      shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for var in VERSION DMG_URL DMG_LENGTH ED_SIGNATURE OUTPUT BUILD_NUMBER; do
    if [ -z "${!var}" ]; then
        echo "error: --$(echo "$var" | tr '[:upper:]' '[:lower:]' | tr '_' '-') is required" >&2
        exit 1
    fi
done

# Strip leading "v" for display version
DISPLAY_VERSION="${VERSION#v}"

# BSD/GNU-compatible UTC date
PUB_DATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')

# Build the <item> block.
# Sparkle 2.x: items WITHOUT <sparkle:channel> are visible to all users
# (the default / stable channel).  Items WITH a channel are opt-in only.
# So we only emit the channel element for non-stable channels.
CHANNEL_ELEMENT=""
if [ "$CHANNEL" != "stable" ]; then
    CHANNEL_ELEMENT="
        <sparkle:channel>$CHANNEL</sparkle:channel>"
fi

ITEM=$(cat <<ITEM_EOF
      <item>
        <title>ArcBox $DISPLAY_VERSION</title>
        <pubDate>$PUB_DATE</pubDate>
        <sparkle:version>$BUILD_NUMBER</sparkle:version>
        <sparkle:shortVersionString>$DISPLAY_VERSION</sparkle:shortVersionString>$CHANNEL_ELEMENT
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

    # Remove existing item with the same marketing version (if any)
    # Use python3 for reliable XML-like text manipulation
    python3 -c "
import sys, re

with open('$EXISTING', 'r') as f:
    content = f.read()

version = '$DISPLAY_VERSION'
item = '''$ITEM'''

# Remove existing item block for the same marketing version.
# Match on sparkle:shortVersionString (current format) or sparkle:version (legacy format
# where marketing version was used directly in sparkle:version).
for tag in ['sparkle:shortVersionString', 'sparkle:version']:
    pattern = r'\s*<item>.*?<' + tag + r'>' + re.escape(version) + r'</' + tag + r'>.*?</item>'
    content = re.sub(pattern, '', content, flags=re.DOTALL)

# Strip <sparkle:channel>stable</sparkle:channel> from legacy items.
# Sparkle 2.x treats items WITHOUT a channel element as the default (stable)
# channel visible to all users; items WITH a channel require explicit opt-in.
content = re.sub(r'\n\s*<sparkle:channel>stable</sparkle:channel>', '', content)

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
