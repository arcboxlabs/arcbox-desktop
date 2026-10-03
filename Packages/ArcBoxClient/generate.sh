#!/bin/bash
# Generate Swift protobuf and gRPC code from arcbox proto definitions.
#
# Proto files are fetched from the arcbox.version GitHub ref by default.
# Pass --local explicitly to generate from the neighboring arcbox checkout.
#
# Prerequisites:
#   brew install protobuf
#
# Usage:
#   cd Packages/ArcBoxClient && ./generate.sh
#   cd Packages/ArcBoxClient && ./generate.sh --local   # force local proto
#   cd Packages/ArcBoxClient && ./generate.sh --remote  # force GitHub fetch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/Sources/ArcBoxClient/Generated"
PROTO_TMPDIR=""

GITHUB_REPO="arcboxlabs/arcbox"
# Pin the proto ref to the arcbox version the app actually embeds (arcbox.version)
# rather than master, so the generated gRPC client matches the daemon it ships
# with. Falls back to master if the pin file is missing.
ARCBOX_VERSION_FILE="${SCRIPT_DIR}/../../arcbox.version"
if [ -f "$ARCBOX_VERSION_FILE" ]; then
    GITHUB_BRANCH="$(tr -d '[:space:]' < "$ARCBOX_VERSION_FILE")"
else
    GITHUB_BRANCH="master"
fi
GITHUB_PROTO_PATH="rpc/arcbox-protocol/proto"

PROTOS=(
    "common.proto"
    "agent.proto"
    "container.proto"
    "image.proto"
    "api.proto"
    "machine.proto"
    "arcbox/sandbox/v1/sandbox.proto"
    "arcbox/sandbox/v1/process.proto"
    "arcbox/sandbox/v1/filesystem.proto"
    "arcbox/sandbox/v1/snapshot.proto"
    "arcbox/sandbox/v1/template.proto"
    "kubernetes.proto"
    "stats.proto"
)

# Parse arguments
FORCE_MODE="${1:-}"

cleanup() {
    if [ -n "$PROTO_TMPDIR" ] && [ -d "$PROTO_TMPDIR" ]; then
        rm -rf "$PROTO_TMPDIR"
    fi
}
trap cleanup EXIT

# Try to find local proto directory
find_local_proto() {
    local candidates=(
        "${SCRIPT_DIR}/../../../arcbox/rpc/arcbox-protocol/proto"
    )
    for dir in "${candidates[@]}"; do
        if [ -d "$dir" ]; then
            echo "$(cd "$dir" && pwd)"
            return 0
        fi
    done
    return 1
}

# Download proto files from GitHub. Progress messages go to stderr so the
# function's stdout is just the tmp directory path captured by callers.
fetch_from_github() {
    PROTO_TMPDIR="$(mktemp -d)"
    echo "Fetching proto files from GitHub (${GITHUB_REPO}@${GITHUB_BRANCH})..." >&2

    for proto in "${PROTOS[@]}"; do
        local url="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${GITHUB_PROTO_PATH}/${proto}"
        mkdir -p "$(dirname "${PROTO_TMPDIR}/${proto}")"
        echo "  Downloading ${proto}" >&2
        if ! curl -fsSL -o "${PROTO_TMPDIR}/${proto}" "$url"; then
            echo "Error: failed to download ${proto} from ${url}" >&2
            exit 1
        fi
    done

    echo "$PROTO_TMPDIR"
}

# Determine proto source
if [ "$FORCE_MODE" = "--local" ]; then
    PROTO_DIR="$(find_local_proto)" || {
        echo "Error: --local specified but local proto directory not found"
        exit 1
    }
    echo "Using local proto: $PROTO_DIR"
elif [ "$FORCE_MODE" = "--remote" ]; then
    PROTO_DIR="$(fetch_from_github)"
    echo "Using GitHub proto: $PROTO_DIR"
else
    PROTO_DIR="$(fetch_from_github)"
    echo "Using GitHub proto: $PROTO_DIR"
fi

echo "Output dir: $OUT_DIR"

# Build protoc plugins from grpc-swift-protobuf.
#
# The SwiftPM scratch dir must live OUTSIDE Packages/: CI cache keys hash
# Packages/** (pr.yml/release.yml "Restore Xcode build cache"), and a .build
# here breaks them — dependency checkouts can carry dangling symlinks that
# hard-fail hashFiles (sentry-cocoa's .claude/skills did), and checked-out
# package manifests pollute the swiftpm cache key.
SCRATCH_DIR="${SCRIPT_DIR}/../../.build/protoc-plugins"
SYSTEM_DEVELOPER_DIR="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/xcode-select -p)"
SWIFT_ENV=(
    /usr/bin/env -i
    "HOME=$HOME"
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
    "DEVELOPER_DIR=$SYSTEM_DEVELOPER_DIR"
)
if [ -n "${TMPDIR:-}" ]; then
    SWIFT_ENV+=("TMPDIR=$TMPDIR")
fi

echo ""
echo "Building protoc plugins..."
cd "$SCRIPT_DIR"
"${SWIFT_ENV[@]}" /usr/bin/xcrun swift build \
    --scratch-path "$SCRATCH_DIR" \
    --product protoc-gen-swift
"${SWIFT_ENV[@]}" /usr/bin/xcrun swift build \
    --scratch-path "$SCRATCH_DIR" \
    --product protoc-gen-grpc-swift

PLUGIN_DIR="$("${SWIFT_ENV[@]}" /usr/bin/xcrun swift build \
    --scratch-path "$SCRATCH_DIR" \
    --show-bin-path)"
export PATH="${PLUGIN_DIR}:${PATH}"

echo "Using protoc-gen-swift: $(which protoc-gen-swift)"
echo "Using protoc-gen-grpc-swift: $(which protoc-gen-grpc-swift)"

# Rebuild the generated tree so removed or relocated proto files cannot leave
# stale Swift sources behind.
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo ""
echo "Generating Swift protobuf code..."
printf '  %s\n' "${PROTOS[@]}"
# One protoc invocation for all files: starts protoc and the plugins once
# instead of per-proto. Output is identical to the per-file loop.
protoc \
    --proto_path="$PROTO_DIR" \
    --swift_out="$OUT_DIR" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$OUT_DIR" \
    --grpc-swift_opt=Visibility=Public \
    "${PROTOS[@]/#/$PROTO_DIR/}"

echo ""
echo "Generated files:"
find "$OUT_DIR" -type f -name '*.swift' -print | sort
echo ""
echo "Done."
