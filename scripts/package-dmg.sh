#!/bin/bash
# Build ArcBox Desktop.app and package it into a signed/notarized DMG.
#
# Usage:
#   scripts/package-dmg.sh [--sign <identity>] [--notarize]
#
# Environment variables:
#   DESKTOP_REPO   - Path to arcbox-desktop-swift checkout (default: script dir/..)
#   BUNDLE_ID      - App bundle identifier (default: com.arcbox.arcbox-desktop-swift)
#   TEAM_ID        - Apple Developer Team ID (required for signing)
#   ARCBOX_DIR     - Path to arcbox checkout (default: DESKTOP_REPO/../arcbox or ./arcbox)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_REPO="${DESKTOP_REPO:-"$(cd "$SCRIPT_DIR/.." && pwd)"}"

# Parse arguments
SIGN_IDENTITY=""
NOTARIZE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        --notarize) NOTARIZE=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Locate arcbox checkout (CI puts it at workspace/arcbox, local dev at ../arcbox)
if [ -d "$DESKTOP_REPO/arcbox" ]; then
    ARCBOX_DIR="${ARCBOX_DIR:-"$DESKTOP_REPO/arcbox"}"
elif [ -d "$DESKTOP_REPO/../arcbox" ]; then
    ARCBOX_DIR="${ARCBOX_DIR:-"$(cd "$DESKTOP_REPO/../arcbox" && pwd)"}"
else
    echo "error: cannot locate arcbox checkout" >&2
    exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-com.arcbox.arcbox-desktop-swift}"
BUILD_DIR="$ARCBOX_DIR/target/dmg-build"
APP_NAME="ArcBox Desktop"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Read version from Xcode project
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' \
    "$DESKTOP_REPO/arcbox-desktop-swift.xcodeproj/project.pbxproj" | head -1 | tr -d ' ')
VERSION="${VERSION:-1.0}"
DMG_NAME="ArcBox-Desktop-${VERSION}-arm64"
DMG_PATH="$ARCBOX_DIR/target/$DMG_NAME.dmg"

echo "=== Building ArcBox Desktop ==="
echo "  Desktop repo : $DESKTOP_REPO"
echo "  Arcbox dir   : $ARCBOX_DIR"
echo "  Bundle ID    : $BUNDLE_ID"
echo "  Version      : $VERSION"
echo "  Sign identity: ${SIGN_IDENTITY:-"(ad-hoc)"}"
echo "  Notarize     : $NOTARIZE"

# ---------------------------------------------------------------------------
# 1. Build Swift app with xcodebuild
# ---------------------------------------------------------------------------
echo "--- Building Swift app ---"

XCODE_FLAGS=(
    -project "$DESKTOP_REPO/arcbox-desktop-swift.xcodeproj"
    -scheme "arcbox-desktop-swift"
    -configuration Release
    -derivedDataPath "$BUILD_DIR/DerivedData"
    ARCBOX_DIR="$ARCBOX_DIR"
)

if [ -n "$SIGN_IDENTITY" ]; then
    XCODE_FLAGS+=(
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM="${TEAM_ID:-}"
    )
fi

xcodebuild build "${XCODE_FLAGS[@]}" | tail -20

# Locate the built .app
BUILT_APP=$(find "$BUILD_DIR/DerivedData/Build/Products/Release" \
    -name "*.app" -maxdepth 1 | head -1)

if [ ! -d "$BUILT_APP" ]; then
    echo "error: .app bundle not found after build" >&2
    exit 1
fi

# Copy to staging area
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"
cp -R "$BUILT_APP" "$APP_BUNDLE"

echo "  App bundle: $APP_BUNDLE"

# ---------------------------------------------------------------------------
# 2. Embed boot-assets
# ---------------------------------------------------------------------------
echo "--- Embedding boot-assets ---"

# Read version from boot-assets.lock.
LOCK_FILE="$ARCBOX_DIR/boot-assets.lock"
if [ ! -f "$LOCK_FILE" ]; then
    echo "error: $LOCK_FILE not found" >&2
    exit 1
fi
BOOT_VERSION=$(grep '^version' "$LOCK_FILE" | head -1 | sed 's/.*= *"\(.*\)"/\1/')
echo "  Boot-asset version: $BOOT_VERSION"

# Locate cached boot-assets (after `abctl boot prefetch`).
BOOT_CACHE=""
for candidate in \
    "$ARCBOX_DIR/target/boot-assets/$BOOT_VERSION" \
    "$HOME/.arcbox/boot/$BOOT_VERSION"; do
    if [ -f "$candidate/manifest.json" ]; then
        BOOT_CACHE="$candidate"
        break
    fi
done

if [ -z "$BOOT_CACHE" ]; then
    echo "error: boot-assets v$BOOT_VERSION not found." >&2
    echo "  Run 'abctl boot prefetch' first." >&2
    exit 1
fi

# Copy boot-assets.lock → Contents/Resources/ (fallback path uses it).
cp "$LOCK_FILE" "$APP_BUNDLE/Contents/Resources/boot-assets.lock"

# Copy boot files → Contents/Resources/boot/{version}/ (matches BootAssetManager.bundledBootDir).
BOOT_DEST="$APP_BUNDLE/Contents/Resources/boot/$BOOT_VERSION"
mkdir -p "$BOOT_DEST"
cp "$BOOT_CACHE/kernel"        "$BOOT_DEST/kernel"
cp "$BOOT_CACHE/rootfs.erofs"  "$BOOT_DEST/rootfs.erofs"
cp "$BOOT_CACHE/manifest.json" "$BOOT_DEST/manifest.json"
echo "  Embedded boot-assets from $BOOT_CACHE → $BOOT_DEST"

# ---------------------------------------------------------------------------
# 3. Embed arcbox CLI if available
# ---------------------------------------------------------------------------
CLI_BIN="$ARCBOX_DIR/target/release/abctl"
if [ -f "$CLI_BIN" ]; then
    echo "--- Embedding abctl CLI ---"
    HELPERS_DIR="$APP_BUNDLE/Contents/Helpers"
    mkdir -p "$HELPERS_DIR"
    cp -f "$CLI_BIN" "$HELPERS_DIR/abctl"
    if [ -n "$SIGN_IDENTITY" ]; then
        codesign --force --options runtime --sign "$SIGN_IDENTITY" \
            --timestamp "$HELPERS_DIR/abctl"
    fi
    echo "  Copied abctl CLI"
fi

# ---------------------------------------------------------------------------
# 4. Re-sign the entire app bundle
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
    echo "--- Signing app bundle ---"
    codesign --force --deep --options runtime \
        --sign "$SIGN_IDENTITY" --timestamp \
        "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "  Signed and verified"
fi

# ---------------------------------------------------------------------------
# 5. Create DMG
# ---------------------------------------------------------------------------
echo "--- Creating DMG ---"
rm -f "$DMG_PATH"

create-dmg \
    --volname "$APP_NAME" \
    --volicon "$APP_BUNDLE/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 150 190 \
    --app-drop-link 450 190 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_BUNDLE" \
    || true  # create-dmg exits non-zero when icon layout fails (cosmetic)

if [ ! -f "$DMG_PATH" ]; then
    echo "error: DMG creation failed" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 6. Sign DMG
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
    echo "--- Signing DMG ---"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

# ---------------------------------------------------------------------------
# 7. Notarize
# ---------------------------------------------------------------------------
if [ "$NOTARIZE" = true ] && [ -n "$SIGN_IDENTITY" ]; then
    echo "--- Notarizing DMG ---"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "arcbox-notarize" \
        --wait --timeout 30m
    xcrun stapler staple "$DMG_PATH"
    echo "  Notarization complete"
fi

echo "=== Done ==="
echo "  DMG: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
