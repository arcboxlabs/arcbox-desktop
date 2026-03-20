#!/bin/bash
set -euo pipefail

# Fetch arcbox binaries (abctl + arcbox-daemon + arcbox-agent) for the Xcode build phase.
# Priority: local build (../arcbox) → version cache → error with instructions.

DAEMON_NAME="com.arcboxlabs.desktop.daemon"
ARCBOX_VERSION=$(tr -d '[:space:]' < "${PROJECT_DIR}/arcbox.version")
CACHE_DIR="${PROJECT_DIR}/.build/arcbox-binaries/${ARCBOX_VERSION}"

LOCAL_DIR="${PROJECT_DIR}/../arcbox/target/release"
LOCAL_AGENT_DIR="${PROJECT_DIR}/../arcbox/target/aarch64-unknown-linux-musl/release"

if [ -f "${LOCAL_DIR}/abctl" ] && [ -f "${LOCAL_DIR}/arcbox-daemon" ]; then
    echo "note: Using local arcbox binaries from ../arcbox/target/release"
    SRC_DIR="${LOCAL_DIR}"
    AGENT_SRC="${LOCAL_AGENT_DIR}/arcbox-agent"
elif [ -f "${CACHE_DIR}/abctl" ] && [ -f "${CACHE_DIR}/arcbox-daemon" ]; then
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

# Copy daemon → Contents/Helpers/
HELPERS_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
mkdir -p "${HELPERS_DIR}"
cp -f "${SRC_DIR}/arcbox-daemon" "${HELPERS_DIR}/${DAEMON_NAME}"

# Sign the daemon binary with the same team identity as the app.
# SMAppService requires that embedded helpers share the app's signing identity.
# Without this, register() fails with "Operation not permitted".
DAEMON_ENTITLEMENTS="${PROJECT_DIR}/ArcBox/DaemonEntitlements.entitlements"
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    codesign --force --options runtime \
        --entitlements "${DAEMON_ENTITLEMENTS}" \
        --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
        "${HELPERS_DIR}/${DAEMON_NAME}"
    echo "note: Signed daemon with identity: ${EXPANDED_CODE_SIGN_IDENTITY}"
elif [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
    codesign --force --options runtime \
        --entitlements "${DAEMON_ENTITLEMENTS}" \
        --sign "${CODE_SIGN_IDENTITY}" \
        "${HELPERS_DIR}/${DAEMON_NAME}"
    echo "note: Signed daemon with identity: ${CODE_SIGN_IDENTITY}"
else
    # Ad-hoc fallback for unsigned development builds.
    codesign --force --options runtime \
        --entitlements "${DAEMON_ENTITLEMENTS}" \
        -s - "${HELPERS_DIR}/${DAEMON_NAME}"
    echo "warning: No signing identity available; daemon signed ad-hoc (SMAppService will not work)"
fi

# Copy com.arcboxlabs.desktop.helper → Contents/Library/HelperTools/
# SMAppService.daemon() expects the helper binary here (matches BundleProgram in plist).
HELPER_SRC="${SRC_DIR}/arcbox-helper"
if [ -f "${HELPER_SRC}" ]; then
    HELPER_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Library/HelperTools"
    mkdir -p "${HELPER_DIR}"
    cp -f "${HELPER_SRC}" "${HELPER_DIR}/com.arcboxlabs.desktop.helper"

    if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
        codesign --force --options runtime \
            --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
            --identifier "com.arcboxlabs.desktop.helper" \
            "${HELPER_DIR}/com.arcboxlabs.desktop.helper"
        echo "note: Signed helper with identity: ${EXPANDED_CODE_SIGN_IDENTITY}"
    elif [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ]; then
        codesign --force --options runtime \
            --sign "${CODE_SIGN_IDENTITY}" \
            --identifier "com.arcboxlabs.desktop.helper" \
            "${HELPER_DIR}/com.arcboxlabs.desktop.helper"
        echo "note: Signed helper with identity: ${CODE_SIGN_IDENTITY}"
    else
        codesign --force -s - "${HELPER_DIR}/com.arcboxlabs.desktop.helper"
        echo "warning: Helper signed ad-hoc (SMAppService.daemon will not work)"
    fi
    echo "note: Embedded com.arcboxlabs.desktop.helper → Library/HelperTools/com.arcboxlabs.desktop.helper"
else
    echo "warning: arcbox-helper not found at ${HELPER_SRC}, skipping"
fi

# Copy abctl CLI → Contents/MacOS/bin/
CLI_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/bin"
mkdir -p "${CLI_DIR}"
cp -f "${SRC_DIR}/abctl" "${CLI_DIR}/abctl"

# Copy arcbox-agent → Contents/Resources/bin/ (seeded to ~/.arcbox/bin/ at launch)
if [ -f "${AGENT_SRC}" ]; then
    AGENT_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources/bin"
    mkdir -p "${AGENT_DIR}"
    cp -f "${AGENT_SRC}" "${AGENT_DIR}/arcbox-agent"
    echo "note: Embedded arcbox-agent → Resources/bin/arcbox-agent"
else
    echo "warning: arcbox-agent not found at ${AGENT_SRC}, skipping"
fi

