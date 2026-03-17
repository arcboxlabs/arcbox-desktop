#!/bin/bash
# Generate Swift protobuf and gRPC code from arcbox proto definitions.
#
# Proto files are fetched from GitHub (arcboxd/arcbox) by default,
# or from a local arcbox checkout if available.
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

GITHUB_REPO="arcbox-labs/arcbox"
GITHUB_BRANCH="main"
GITHUB_PROTO_PATH="rpc/arcbox-protocol/proto"

PROTOS=(
    "common.proto"
    "container.proto"
    "image.proto"
    "api.proto"
    "machine.proto"
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

# Download proto files from GitHub
fetch_from_github() {
    PROTO_TMPDIR="$(mktemp -d)"
    echo "Fetching proto files from GitHub (${GITHUB_REPO}@${GITHUB_BRANCH})..."

    for proto in "${PROTOS[@]}"; do
        local url="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${GITHUB_PROTO_PATH}/${proto}"
        echo "  Downloading ${proto}"
        if ! curl -fsSL -o "${PROTO_TMPDIR}/${proto}" "$url"; then
            echo "Error: failed to download ${proto} from ${url}"
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
    # Auto: prefer local, fallback to GitHub
    if PROTO_DIR="$(find_local_proto)"; then
        echo "Using local proto: $PROTO_DIR"
    else
        PROTO_DIR="$(fetch_from_github)"
        echo "Using GitHub proto: $PROTO_DIR"
    fi
fi

echo "Output dir: $OUT_DIR"

# Build protoc plugins from grpc-swift-protobuf
echo ""
echo "Building protoc plugins..."
cd "$SCRIPT_DIR"
swift build --product protoc-gen-swift 2>&1 | tail -1
swift build --product protoc-gen-grpc-swift 2>&1 | tail -1

PLUGIN_DIR="$(swift build --show-bin-path)"
export PATH="${PLUGIN_DIR}:${PATH}"

echo "Using protoc-gen-swift: $(which protoc-gen-swift)"
echo "Using protoc-gen-grpc-swift: $(which protoc-gen-grpc-swift)"

# Clean old generated files
rm -f "$OUT_DIR"/*.swift

echo ""
echo "Generating Swift protobuf code..."
for proto in "${PROTOS[@]}"; do
    echo "  $proto"
    protoc \
        --proto_path="$PROTO_DIR" \
        --swift_out="$OUT_DIR" \
        --swift_opt=Visibility=Public \
        --grpc-swift_out="$OUT_DIR" \
        --grpc-swift_opt=Visibility=Public \
        "$PROTO_DIR/$proto"
done

echo ""
echo "Generated files:"
ls -la "$OUT_DIR"/*.swift 2>/dev/null || echo "  (none)"
echo ""
echo "Done."
