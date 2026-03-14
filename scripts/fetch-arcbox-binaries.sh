#!/bin/bash
set -euo pipefail

# Fetch arcbox binaries (abctl + arcbox-daemon + arcbox-agent) for the Xcode build phase.
# Priority: CI pre-downloaded → local cache → download from GitHub releases.

DAEMON_NAME="com.arcboxlabs.desktop.daemon"
ARCBOX_VERSION=$(tr -d '[:space:]' < "${PROJECT_DIR}/arcbox.version")
CACHE_DIR="${PROJECT_DIR}/.build/arcbox-binaries/${ARCBOX_VERSION}"

# CI path: pre-downloaded via workflow, symlinked at ../arcbox
# Only check this in CI to avoid using stale local builds from ../arcbox
CI_DIR="${PROJECT_DIR}/../arcbox/target/release"
CI_AGENT_DIR="${PROJECT_DIR}/../arcbox/target/aarch64-unknown-linux-musl/release"

if [ "${CI:-}" = "true" ] && [ -f "${CI_DIR}/abctl" ] && [ -f "${CI_DIR}/arcbox-daemon" ]; then
    echo "note: Using CI pre-downloaded arcbox binaries"
    SRC_DIR="${CI_DIR}"
    AGENT_SRC="${CI_AGENT_DIR}/arcbox-agent"
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
