#!/bin/bash
set -euo pipefail

# Embed arcbox binaries into the Xcode app bundle.
#
# This build phase script:
#   1. Builds Rust binaries via `make build-rust` in the arcbox repo (incremental, ~0.3s no-op)
#   2. Copies binaries into the app bundle (incremental, skips unchanged)
#   3. Signs CLI/helper (daemon is already signed by make sign-daemon with Developer ID)
#
# The daemon requires Developer ID signing for virtualization/hypervisor entitlements,
# even in Debug builds. `make sign-daemon` in the arcbox repo handles this.
#
# Set SKIP_RUST_BUILD=1 to skip entirely (used by CI for Swift-only checks).

# Xcode strips PATH to /usr/bin:/bin:/usr/sbin:/sbin.
# Ensure cargo and homebrew tools are reachable.
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

if [ "${SKIP_RUST_BUILD:-0}" = "1" ]; then
    echo "note: SKIP_RUST_BUILD=1, skipping binary embedding"
    exit 0
fi

DAEMON_NAME="com.arcboxlabs.desktop.daemon"
SCRIPT_DIR="${PROJECT_DIR}/scripts"
ARCBOX_VERSION=$(tr -d '[:space:]' < "${PROJECT_DIR}/arcbox.version")
CACHE_DIR="${PROJECT_DIR}/.build/arcbox-binaries/${ARCBOX_VERSION}"

# Support ARCBOX_DIR override (e.g., CI checks out at ${PROJECT_DIR}/arcbox).
if [ -n "${ARCBOX_DIR:-}" ]; then
    ARCBOX_REPO="${ARCBOX_DIR}"
elif [ -d "${PROJECT_DIR}/arcbox" ] && [ -f "${PROJECT_DIR}/arcbox/Cargo.toml" ]; then
    ARCBOX_REPO="${PROJECT_DIR}/arcbox"
elif [ -d "${PROJECT_DIR}/../arcbox" ] && [ -f "${PROJECT_DIR}/../arcbox/Cargo.toml" ]; then
    ARCBOX_REPO="${PROJECT_DIR}/../arcbox"
else
    ARCBOX_REPO=""
fi
LOCAL_DIR="${ARCBOX_REPO:+${ARCBOX_REPO}/target/release}"
LOCAL_AGENT_DIR="${ARCBOX_REPO:+${ARCBOX_REPO}/target/aarch64-unknown-linux-musl/release}"

is_macho() { [ -f "$1" ] && head -c4 "$1" | xxd -p | grep -qE '^(cffaedfe|cafebabe)'; }

# Incremental copy: only copies when content differs.
# Returns 0 if copied (changed), 1 if unchanged.
sync_binary() {
    local src="$1" dst="$2"
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
        cp -f "$src" "$dst"
        return 0
    fi
    return 1
}

# Verify a binary's code signature is valid.
# Usage: verify_signature <binary> [--check-entitlements]
verify_signature() {
    local binary="$1"
    local check_entitlements="${2:-}"
    if ! codesign --verify --strict "$binary" 2>/dev/null; then
        echo "warning: $binary has invalid or missing code signature"
        return 1
    fi
    if [ "$check_entitlements" = "--check-entitlements" ]; then
        local entitlements
        entitlements=$(codesign -d --entitlements - "$binary" 2>/dev/null || true)
        if ! echo "$entitlements" | grep -q "com.apple.security.virtualization"; then
            echo "error: $binary is missing com.apple.security.virtualization entitlement" >&2
            return 1
        fi
        if ! echo "$entitlements" | grep -q "com.apple.security.hypervisor"; then
            echo "error: $binary is missing com.apple.security.hypervisor entitlement" >&2
            return 1
        fi
    fi
    return 0
}

# ── Build ────────────────────────────────────────────────
# If the arcbox repo is available, build everything (incremental, ~0.3s no-op).
# Calls arcbox-desktop's `make build-rust`, which delegates to arcbox repo:
#   build-cli, build-helper, sign-daemon (Developer ID), build-agent (soft-fail)
if [ -n "${ARCBOX_REPO}" ] && [ -f "${ARCBOX_REPO}/Makefile" ]; then
    echo "note: Building arcbox binaries (incremental)..."
    make -C "${PROJECT_DIR}" build-rust ARCBOX_DIR="${ARCBOX_REPO}"
fi

# ── Resolve source ───────────────────────────────────────
if [ -n "${LOCAL_DIR}" ] && [ -f "${LOCAL_DIR}/abctl" ] && [ -f "${LOCAL_DIR}/arcbox-daemon" ]; then
    if ! is_macho "${LOCAL_DIR}/arcbox-daemon"; then
        echo "error: ${LOCAL_DIR}/arcbox-daemon is not a valid Mach-O binary" >&2
        exit 1
    fi
    echo "note: Using local arcbox binaries from ${LOCAL_DIR}"
    SRC_DIR="${LOCAL_DIR}"
    AGENT_SRC="${LOCAL_AGENT_DIR}/arcbox-agent"
elif [ -f "${CACHE_DIR}/abctl" ] && [ -f "${CACHE_DIR}/arcbox-daemon" ]; then
    if ! is_macho "${CACHE_DIR}/arcbox-daemon"; then
        echo "error: Cached arcbox-daemon is not a valid Mach-O binary." >&2
        echo "  Remove the stale cache and rebuild:"
        echo "    rm -rf ${CACHE_DIR}"
        exit 1
    fi
    echo "note: Using cached arcbox ${ARCBOX_VERSION} binaries"
    SRC_DIR="${CACHE_DIR}"
    AGENT_SRC="${CACHE_DIR}/arcbox-agent"
else
    echo "error: arcbox ${ARCBOX_VERSION} binaries not found."
    echo ""
    echo "Option 1: Build from source"
    echo "  cd ${PROJECT_DIR}/../arcbox && cargo build --release"
    echo ""
    echo "Option 2: Download from GitHub Releases"
    echo "  Download ${ARCBOX_VERSION} from https://github.com/arcboxlabs/arcbox/releases/tag/${ARCBOX_VERSION}"
    echo "  Extract and place abctl, arcbox-daemon, arcbox-agent into:"
    echo "    ${CACHE_DIR}/"
    exit 1
fi

# ── Embed daemon → Contents/Frameworks/*.app ─────────────
# The daemon is wrapped in a minimal .app bundle so it can carry its own
# embedded.provisionprofile. This lets AMFI validate restricted entitlements
# (com.apple.vm.networking) on the user's machine.
FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Frameworks"
DAEMON_BUNDLE="${FRAMEWORKS_DIR}/${DAEMON_NAME}.app"
DAEMON_BINARY="${DAEMON_BUNDLE}/Contents/MacOS/${DAEMON_NAME}"

# Rebuild bundle if the source binary changed.
if [ ! -f "${DAEMON_BINARY}" ] || ! cmp -s "${SRC_DIR}/arcbox-daemon" "${DAEMON_BINARY}"; then
    echo "note: Building daemon .app bundle..."
    /usr/bin/python3 "${SCRIPT_DIR}/bundle-daemon.py" \
        "${SRC_DIR}/arcbox-daemon" \
        "${FRAMEWORKS_DIR}" \
        --version "${ARCBOX_VERSION}"
    echo "note: Daemon bundle created at ${DAEMON_BUNDLE}"
else
    echo "note: Daemon bundle unchanged, skipping rebuild"
fi

# Verify daemon signature and required entitlements.
# In dev builds with ad-hoc signing (CODE_SIGN_IDENTITY=-), the bundle-daemon.py
# re-signs with ad-hoc which strips entitlements. Only check entitlements when
# a real signing identity is available.
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    if ! verify_signature "${DAEMON_BINARY}" --check-entitlements; then
        echo "error: Daemon at ${DAEMON_BINARY} must be signed with virtualization/hypervisor entitlements." >&2
        echo "  Run: make -C $(dirname ${ARCBOX_REPO:-../arcbox}) sign-daemon" >&2
        exit 1
    fi
elif ! verify_signature "${DAEMON_BINARY}"; then
    echo "warning: Daemon signature invalid (ad-hoc builds skip entitlement check)"
fi

# Clean up legacy Helpers/ location if present (migration from bare binary).
LEGACY_DAEMON="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/${DAEMON_NAME}"
if [ -f "${LEGACY_DAEMON}" ]; then
    rm -f "${LEGACY_DAEMON}"
    echo "note: Removed legacy daemon at Helpers/${DAEMON_NAME}"
fi

# ── Embed abctl → Contents/MacOS/bin/ ────────────────────
CLI_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/bin"
mkdir -p "${CLI_DIR}"
if sync_binary "${SRC_DIR}/abctl" "${CLI_DIR}/abctl"; then
    # abctl doesn't need special entitlements; sign with whatever identity is available.
    if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
        codesign --force --options runtime --timestamp \
            --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
            --identifier "com.arcboxlabs.desktop.abctl" \
            "${CLI_DIR}/abctl"
    elif [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
        codesign --force --options runtime \
            --sign "${CODE_SIGN_IDENTITY}" \
            --identifier "com.arcboxlabs.desktop.abctl" \
            "${CLI_DIR}/abctl"
    else
        codesign --force -s - "${CLI_DIR}/abctl"
    fi
    echo "note: Embedded and signed abctl → MacOS/bin/abctl"
else
    # Binary unchanged; verify existing signature is still valid.
    if ! verify_signature "${CLI_DIR}/abctl"; then
        echo "warning: abctl signature invalid, consider cleaning build"
    fi
    echo "note: abctl unchanged, skipping copy"
fi

# ── Embed arcbox-helper → Contents/MacOS/bin/ ────────────
HELPER_SRC="${SRC_DIR}/arcbox-helper"
if [ -f "${HELPER_SRC}" ]; then
    if sync_binary "${HELPER_SRC}" "${CLI_DIR}/arcbox-helper"; then
        if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
            codesign --force --options runtime --timestamp \
                --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
                --identifier "com.arcboxlabs.desktop.helper" \
                "${CLI_DIR}/arcbox-helper"
        elif [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
            codesign --force --options runtime \
                --sign "${CODE_SIGN_IDENTITY}" \
                --identifier "com.arcboxlabs.desktop.helper" \
                "${CLI_DIR}/arcbox-helper"
        else
            codesign --force -s - "${CLI_DIR}/arcbox-helper"
        fi
        echo "note: Embedded and signed arcbox-helper → MacOS/bin/arcbox-helper"
    else
        # Binary unchanged; verify existing signature is still valid.
        if ! verify_signature "${CLI_DIR}/arcbox-helper"; then
            echo "warning: arcbox-helper signature invalid, consider cleaning build"
        fi
        echo "note: arcbox-helper unchanged, skipping copy"
    fi
else
    echo "warning: arcbox-helper not found at ${HELPER_SRC}, skipping"
fi

# ── Embed arcbox-agent → Contents/Resources/bin/ ─────────
# Linux musl binary — no macOS signing needed.
if [ -f "${AGENT_SRC}" ]; then
    AGENT_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources/bin"
    mkdir -p "${AGENT_DIR}"
    if sync_binary "${AGENT_SRC}" "${AGENT_DIR}/arcbox-agent"; then
        echo "note: Embedded arcbox-agent → Resources/bin/arcbox-agent"
    else
        echo "note: arcbox-agent unchanged, skipping copy"
    fi
else
    echo "warning: arcbox-agent not found at ${AGENT_SRC}, skipping"
fi
