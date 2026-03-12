#!/bin/bash
set -euo pipefail

# Fetch arcbox binaries (abctl + arcbox-daemon) for the Xcode build phase.
# Priority: CI pre-downloaded → local cache → download from GitHub releases.

DAEMON_NAME="io.arcbox.desktop.daemon"
ARCBOX_VERSION=$(tr -d '[:space:]' < "${PROJECT_DIR}/arcbox.version")
CACHE_DIR="${PROJECT_DIR}/.build/arcbox-binaries/${ARCBOX_VERSION}"

# CI path: pre-downloaded via workflow, symlinked at ../arcbox
# Only check this in CI to avoid using stale local builds from ../arcbox
CI_DIR="${PROJECT_DIR}/../arcbox/target/release"

if [ "${CI:-}" = "true" ] && [ -f "${CI_DIR}/abctl" ] && [ -f "${CI_DIR}/arcbox-daemon" ]; then
    echo "note: Using CI pre-downloaded arcbox binaries"
    SRC_DIR="${CI_DIR}"
elif [ -f "${CACHE_DIR}/abctl" ] && [ -f "${CACHE_DIR}/arcbox-daemon" ]; then
    echo "note: Using cached arcbox ${ARCBOX_VERSION} binaries"
    SRC_DIR="${CACHE_DIR}"
else
    echo "note: Downloading arcbox ${ARCBOX_VERSION} binaries..."
    DOWNLOAD_DIR="$(mktemp -d)"
    trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

    gh release download "${ARCBOX_VERSION}" \
        --repo arcboxlabs/arcbox \
        --dir "$DOWNLOAD_DIR" \
        --skip-existing

    for tarball in "$DOWNLOAD_DIR"/*.tar.gz; do
        [ -f "$tarball" ] && tar xzf "$tarball" -C "$DOWNLOAD_DIR"
    done

    CLI_BIN=$(find "$DOWNLOAD_DIR" -type f -name "abctl" | head -1)
    DAEMON_BIN=$(find "$DOWNLOAD_DIR" -type f -name "arcbox-daemon" | head -1)

    if [ -z "$CLI_BIN" ] || [ -z "$DAEMON_BIN" ]; then
        echo "error: Could not find abctl or arcbox-daemon in release ${ARCBOX_VERSION}"
        exit 1
    fi

    mkdir -p "${CACHE_DIR}"
    cp "$CLI_BIN" "${CACHE_DIR}/abctl"
    cp "$DAEMON_BIN" "${CACHE_DIR}/arcbox-daemon"
    chmod +x "${CACHE_DIR}/abctl" "${CACHE_DIR}/arcbox-daemon"
    echo "note: Downloaded and cached at ${CACHE_DIR}"
    SRC_DIR="${CACHE_DIR}"
fi

# Copy daemon → Contents/Helpers/
HELPERS_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
mkdir -p "${HELPERS_DIR}"
cp -f "${SRC_DIR}/arcbox-daemon" "${HELPERS_DIR}/${DAEMON_NAME}"

# Copy abctl CLI → Contents/MacOS/bin/
CLI_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/bin"
mkdir -p "${CLI_DIR}"
cp -f "${SRC_DIR}/abctl" "${CLI_DIR}/abctl"
