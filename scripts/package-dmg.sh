#!/bin/bash
# Build ArcBox Desktop.app and package it into a signed/notarized DMG.
#
# Usage:
#   scripts/package-dmg.sh [--sign <identity>] [--notarize]
#
# Environment variables:
#   DESKTOP_REPO   - Path to arcbox-desktop checkout (default: script dir/..)
#   BUNDLE_ID      - App bundle identifier (default: com.arcboxlabs.desktop)
#   TEAM_ID        - Apple Developer Team ID (required for signing)
#   ARCBOX_DIR     - Path to arcbox checkout (default: DESKTOP_REPO/../arcbox or ./arcbox)
#   PSTRAMP_DIR    - Path to pstramp checkout (default: ARCBOX_DIR/../pstramp)
#
# App bundle layout (matches OrbStack conventions):
#
#   Contents/
#   ├── MacOS/
#   │   ├── ArcBox Desktop          # Main GUI app
#   │   ├── pstramp                 # Process spawn trampoline
#   │   ├── bin/
#   │   │   └── abctl               # CLI binary
#   │   └── xbin/
#   │       ├── docker              # Docker CLI tools
#   │       ├── docker-buildx
#   │       ├── docker-compose
#   │       └── docker-credential-osxkeychain
#   ├── Helpers/
#   │   └── com.arcboxlabs.desktop.daemon
#   ├── Resources/
#   │   ├── assets.lock
#   │   ├── assets/{version}/       # Boot assets (kernel, rootfs, manifest)
#   │   ├── bin/
#   │   │   └── arcbox-agent        # Guest agent (Linux musl binary)
#   │   ├── runtime/                # Runtime binaries (mirrors ~/.arcbox/runtime/)
#   │   └── completions/{bash,zsh,fish}/

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

# Sign a binary with hardened runtime. No-op when SIGN_IDENTITY is empty.
sign_binary() {
    local target="$1"
    shift
    if [ -n "$SIGN_IDENTITY" ]; then
        codesign --force --options runtime --sign "$SIGN_IDENTITY" \
            --timestamp "$@" "$target"
    fi
}

BUNDLE_ID="${BUNDLE_ID:-com.arcboxlabs.desktop}"
BUILD_DIR="$ARCBOX_DIR/target/dmg-build"
APP_NAME="ArcBox Desktop"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Version can be passed via VERSION env var; otherwise read from Version.xcconfig.
if [ -z "${VERSION:-}" ]; then
    VERSION=$(sed -n 's/^MARKETING_VERSION *= *\(.*\)/\1/p' \
        "$DESKTOP_REPO/Version.xcconfig" | sed 's/ *\/\/.*//' | tr -d ' ')
    VERSION="${VERSION:-0.0.0}"
fi
# Strip leading "v" prefix if present (workflow passes v1.2.3, we need 1.2.3).
VERSION="${VERSION#v}"
BUILD_NUMBER=$(git -C "$DESKTOP_REPO" rev-list --count HEAD)
DMG_NAME="ArcBox-Desktop-${VERSION}-arm64"
DMG_PATH="$ARCBOX_DIR/target/$DMG_NAME.dmg"

echo "=== Building ArcBox Desktop ==="
echo "  Desktop repo : $DESKTOP_REPO"
echo "  Arcbox dir   : $ARCBOX_DIR"
echo "  Bundle ID    : $BUNDLE_ID"
echo "  Version      : $VERSION"
echo "  Build number : $BUILD_NUMBER"
echo "  Sign identity: ${SIGN_IDENTITY:-"(ad-hoc)"}"
echo "  Notarize     : $NOTARIZE"

# ---------------------------------------------------------------------------
# 1. Build Swift app with xcodebuild
# ---------------------------------------------------------------------------
echo "--- Building Swift app ---"

DERIVED_DATA="$DESKTOP_REPO/.build/DerivedData"
SPM_CLONES="/tmp/arcbox-spm-packages"

XCODE_FLAGS=(
    -project "$DESKTOP_REPO/ArcBox.xcodeproj"
    -scheme "ArcBox"
    -configuration Release
    -derivedDataPath "$DERIVED_DATA"
    -clonedSourcePackagesDirPath "$SPM_CLONES"
    -skipPackagePluginValidation
    ARCBOX_DIR="$ARCBOX_DIR"
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)

if [ -n "$SIGN_IDENTITY" ]; then
    XCODE_FLAGS+=(
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM="${TEAM_ID:-}"
    )
fi

# Pass Sparkle feed URL as command-line build setting (xcconfig can't handle // in URLs)
if [ -n "${SPARKLE_FEED_URL:-}" ]; then
    XCODE_FLAGS+=("INFOPLIST_KEY_SUFeedURL=$SPARKLE_FEED_URL")
fi

xcodebuild build "${XCODE_FLAGS[@]}" | tail -20

# Locate the built .app
BUILT_APP=$(find "$DERIVED_DATA/Build/Products/Release" \
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
# 2. Embed boot-assets → Contents/Resources/assets/{version}/
# ---------------------------------------------------------------------------
echo "--- Embedding boot-assets ---"

# Read boot version from assets.lock.
LOCK_FILE="$ARCBOX_DIR/assets.lock"
if [ ! -f "$LOCK_FILE" ]; then
    echo "error: $LOCK_FILE not found" >&2
    exit 1
fi
BOOT_VERSION=$(awk '/^\[boot\]/,0' "$LOCK_FILE" | grep '^version' | head -1 | sed 's/.*= *"\(.*\)"/\1/')
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

# Copy assets.lock → Contents/Resources/
cp "$LOCK_FILE" "$APP_BUNDLE/Contents/Resources/assets.lock"

# Copy boot files → Contents/Resources/assets/{version}/
BOOT_DEST="$APP_BUNDLE/Contents/Resources/assets/$BOOT_VERSION"
mkdir -p "$BOOT_DEST"
cp "$BOOT_CACHE/kernel"        "$BOOT_DEST/kernel"
cp "$BOOT_CACHE/rootfs.erofs"  "$BOOT_DEST/rootfs.erofs"
cp "$BOOT_CACHE/manifest.json" "$BOOT_DEST/manifest.json"
echo "  Embedded boot-assets from $BOOT_CACHE → $BOOT_DEST"

# ---------------------------------------------------------------------------
# 3. Embed abctl CLI → Contents/MacOS/bin/abctl
# ---------------------------------------------------------------------------
CLI_BIN="$ARCBOX_DIR/target/release/abctl"
if [ -f "$CLI_BIN" ]; then
    echo "--- Embedding abctl CLI ---"
    BIN_DIR="$APP_BUNDLE/Contents/MacOS/bin"
    mkdir -p "$BIN_DIR"
    cp -f "$CLI_BIN" "$BIN_DIR/abctl"
    sign_binary "$BIN_DIR/abctl"
    echo "  Copied abctl → MacOS/bin/abctl"
fi

# ---------------------------------------------------------------------------
# 3.5. Embed arcbox-agent → Contents/Resources/bin/arcbox-agent
# ---------------------------------------------------------------------------
AGENT_BIN="$ARCBOX_DIR/target/aarch64-unknown-linux-musl/release/arcbox-agent"
if [ -f "$AGENT_BIN" ]; then
    echo "--- Embedding arcbox-agent ---"
    AGENT_DIR="$APP_BUNDLE/Contents/Resources/bin"
    mkdir -p "$AGENT_DIR"
    cp -f "$AGENT_BIN" "$AGENT_DIR/arcbox-agent"
    echo "  Copied arcbox-agent → Resources/bin/arcbox-agent"
else
    echo "  Warning: arcbox-agent not found at $AGENT_BIN"
    echo "  Build with: cargo build -p arcbox-agent --target aarch64-unknown-linux-musl --release"
fi

# ---------------------------------------------------------------------------
# 4. Embed Docker CLI tools → Contents/MacOS/xbin/
# ---------------------------------------------------------------------------
echo "--- Embedding Docker CLI tools ---"

DOCKER_TOOLS_SRC="$HOME/.arcbox/runtime/bin"
DOCKER_DEST="$APP_BUNDLE/Contents/MacOS/xbin"
DOCKER_TOOLS=(docker docker-buildx docker-compose docker-credential-osxkeychain)
DOCKER_EMBEDDED=0

mkdir -p "$DOCKER_DEST"
for tool in "${DOCKER_TOOLS[@]}"; do
    if [ -f "$DOCKER_TOOLS_SRC/$tool" ]; then
        cp -f "$DOCKER_TOOLS_SRC/$tool" "$DOCKER_DEST/$tool"
        sign_binary "$DOCKER_DEST/$tool"
        echo "  Embedded $tool → MacOS/xbin/$tool"
        DOCKER_EMBEDDED=$((DOCKER_EMBEDDED + 1))
    fi
done

if [ "$DOCKER_EMBEDDED" -eq 0 ]; then
    echo "  Warning: no Docker tools found at $DOCKER_TOOLS_SRC"
    echo "  Run 'abctl docker setup' to download them first."
    rmdir "$DOCKER_DEST" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 5. Embed runtime binaries → Contents/Resources/runtime-bin/
# ---------------------------------------------------------------------------
echo "--- Preparing and embedding runtime binaries ---"

# Use abctl to ensure all runtime binaries (dockerd, containerd, runc, k3s,
# firecracker, etc.) are downloaded and cached at ~/.arcbox/runtime/.
# This is the same command users run manually; it reads the manifest from the
# boot-asset cache and downloads any missing binaries from the CDN.
if [ -f "$CLI_BIN" ]; then
    echo "  Running abctl boot prefetch..."
    "$CLI_BIN" boot prefetch || {
        echo "error: abctl boot prefetch failed" >&2
        exit 1
    }
else
    echo "  Warning: abctl not found at $CLI_BIN, skipping prefetch"
fi

# Copy the entire runtime directory tree into the bundle.
# The directory mirrors what prepare_binaries() expects:
#   runtime/bin/   — dockerd, containerd, runc, k3s, ...
#   runtime/kernel/ — vmlinux (install_dir=kernel)
RUNTIME_SRC="$HOME/.arcbox/runtime"
RUNTIME_DEST="$APP_BUNDLE/Contents/Resources/runtime"
RUNTIME_EMBEDDED=0

if [ -d "$RUNTIME_SRC" ]; then
    # Copy directory structure, only executable files (skip .sha256, .tmp, etc.)
    find "$RUNTIME_SRC" -type f -perm +111 | while read -r src_file; do
        rel="${src_file#"$RUNTIME_SRC/"}"
        dest_file="$RUNTIME_DEST/$rel"
        mkdir -p "$(dirname "$dest_file")"
        cp -f "$src_file" "$dest_file"
        sign_binary "$dest_file"
        echo "  Embedded $rel"
    done
    RUNTIME_EMBEDDED=$(find "$RUNTIME_DEST" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$RUNTIME_EMBEDDED" -eq 0 ]; then
    echo "  Warning: no runtime binaries found at $RUNTIME_SRC"
    echo "  Run 'abctl boot prefetch' to download them first."
    rm -rf "$RUNTIME_DEST" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 6. Embed Docker shell completions → Contents/Resources/completions/
# ---------------------------------------------------------------------------
echo "--- Embedding Docker completions ---"

COMP_SRC="$HOME/.arcbox/completions"
COMP_DEST="$APP_BUNDLE/Contents/Resources/completions"

for shell_dir in zsh bash fish; do
    src_dir="$COMP_SRC/$shell_dir"
    if [ -d "$src_dir" ] && [ "$(ls -A "$src_dir" 2>/dev/null)" ]; then
        mkdir -p "$COMP_DEST/$shell_dir"
        cp -f "$src_dir"/* "$COMP_DEST/$shell_dir/"
        echo "  Copied $shell_dir completions"
    fi
done

# ---------------------------------------------------------------------------
# 7. Embed pstramp → Contents/MacOS/pstramp
# ---------------------------------------------------------------------------
echo "--- Embedding pstramp ---"

PSTRAMP_SRC=""
PSTRAMP_DIR="${PSTRAMP_DIR:-""}"
for candidate in \
    "$PSTRAMP_DIR/target/release/pstramp" \
    "$ARCBOX_DIR/../pstramp/target/release/pstramp"; do
    if [ -f "$candidate" ]; then
        PSTRAMP_SRC="$candidate"
        break
    fi
done

if [ -n "$PSTRAMP_SRC" ]; then
    cp -f "$PSTRAMP_SRC" "$APP_BUNDLE/Contents/MacOS/pstramp"
    sign_binary "$APP_BUNDLE/Contents/MacOS/pstramp"
    echo "  Embedded pstramp from $PSTRAMP_SRC"
else
    echo "  Warning: pstramp not found. Build it with: cargo build --release -p pstramp"
fi

# ---------------------------------------------------------------------------
# 8. Re-sign the entire app bundle
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
    echo "--- Signing app bundle ---"

    DAEMON_PATH="$APP_BUNDLE/Contents/Helpers/com.arcboxlabs.desktop.daemon"
    DAEMON_ENTITLEMENTS="$DESKTOP_REPO/ArcBox/DaemonEntitlements.entitlements"

    # Deep-sign the entire bundle first (covers frameworks, dylibs, etc.).
    codesign --force --deep --options runtime \
        --sign "$SIGN_IDENTITY" --timestamp \
        "$APP_BUNDLE"

    # Re-sign the daemon helper WITH its entitlements (--deep strips them).
    if [ -f "$DAEMON_PATH" ]; then
        sign_binary "$DAEMON_PATH" \
            --identifier "com.arcboxlabs.desktop.daemon" \
            --entitlements "$DAEMON_ENTITLEMENTS"
        echo "  Signed daemon with virtualization entitlement"
    fi

    # Re-sign ArcBoxHelper (privileged helper for root-level operations).
    HELPER_PATH="$APP_BUNDLE/Contents/Library/HelperTools/ArcBoxHelper"
    HELPER_ENTITLEMENTS="$DESKTOP_REPO/ArcBoxHelper/ArcBoxHelper.entitlements"
    if [ -f "$HELPER_PATH" ]; then
        sign_binary "$HELPER_PATH" \
            --identifier "com.arcboxlabs.desktop.helper" \
            --entitlements "$HELPER_ENTITLEMENTS"
        echo "  Signed ArcBoxHelper with hardened runtime"
    fi

    # Re-sign the outer app (nested code changed, so the seal must be refreshed).
    sign_binary "$APP_BUNDLE"

    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "  Signed and verified"
fi

# ---------------------------------------------------------------------------
# 9. Create DMG
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
# 10. Sign DMG
# ---------------------------------------------------------------------------
if [ -n "$SIGN_IDENTITY" ]; then
    echo "--- Signing DMG ---"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

# ---------------------------------------------------------------------------
# 11. Notarize
# ---------------------------------------------------------------------------
if [ "$NOTARIZE" = true ] && [ -n "$SIGN_IDENTITY" ]; then
    echo "--- Notarizing DMG ---"
    SUBMIT_OUT=$(xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "arcbox-notarize" \
        --wait --timeout 90m 2>&1) || true
    echo "$SUBMIT_OUT"

    # Extract submission ID for log retrieval.
    SUBMISSION_ID=$(echo "$SUBMIT_OUT" | awk '/^  id:/{print $2; exit}')

    if echo "$SUBMIT_OUT" | grep -q "status: Accepted"; then
        xcrun stapler staple "$DMG_PATH"
        echo "  Notarization complete"
    else
        echo "--- Notarization FAILED ---"
        if echo "$SUBMIT_OUT" | grep -q "status: Invalid"; then
            echo "  Status: REJECTED by Apple"
        else
            echo "  Status: did not reach 'Accepted' (timed out or unknown error)"
        fi
        if [ -n "$SUBMISSION_ID" ]; then
            echo "--- Fetching notarization log ---"
            xcrun notarytool log "$SUBMISSION_ID" \
                --keychain-profile "arcbox-notarize" 2>&1 || true
        fi
        exit 1
    fi
fi

echo "=== Done ==="
echo "  DMG: $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
