#!/bin/bash
# Generate Swift protobuf and gRPC code from the runner agent local control API.
#
# Prerequisites:
#   brew install protobuf
#
# Usage:
#   cd Packages/RunnerAgentClient && ./generate.sh
#   RUNNER_CONTROL_PROTO_REPO=/path/to/arcbox ./generate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/Sources/RunnerAgentClient/Generated"
PROTO_ROOT_RELATIVE="runner/arcbox-runner-control-proto/proto"
PROTO_RELATIVE="${PROTO_ROOT_RELATIVE}/arcbox/runner/control/v1/control.proto"
SOURCE_FILE="${SCRIPT_DIR}/PROTO_SOURCE"

PROTOS=(
    "arcbox/runner/control/v1/control.proto"
)

find_local_repo() {
    local candidates=(
        "${SCRIPT_DIR}/../../../arcbox"
    )
    for dir in "${candidates[@]}"; do
        if [ -d "$dir" ]; then
            echo "$(cd "$dir" && pwd)"
            return 0
        fi
    done
    return 1
}

PROTO_REPO="${RUNNER_CONTROL_PROTO_REPO:-}"
if [ -z "$PROTO_REPO" ]; then
    PROTO_REPO="$(find_local_repo)" || {
        echo "Error: local arcbox repository not found" >&2
        echo "Expected sibling checkout at ../../../arcbox or RUNNER_CONTROL_PROTO_REPO" >&2
        exit 1
    }
else
    PROTO_REPO="$(cd "$PROTO_REPO" && pwd)"
fi

PROTO_ROOT="${PROTO_REPO}/${PROTO_ROOT_RELATIVE}"
PROTO_FILE="${PROTO_REPO}/${PROTO_RELATIVE}"

if [ ! -f "$PROTO_FILE" ]; then
    echo "Error: runner agent control proto not found at $PROTO_FILE" >&2
    exit 1
fi

SOURCE_COMMIT="$(git -C "$PROTO_REPO" rev-parse HEAD)"
if ! git -C "$PROTO_REPO" diff --quiet HEAD -- "$PROTO_RELATIVE"; then
    echo "Error: runner agent control proto has uncommitted changes" >&2
    exit 1
fi
PROTO_SHA256="$(shasum -a 256 "$PROTO_FILE" | cut -d ' ' -f 1)"

mkdir -p "$OUT_DIR"

echo "Using local runner agent control proto: $PROTO_ROOT"
echo "Source commit: $SOURCE_COMMIT"
echo "Proto SHA-256: $PROTO_SHA256"
echo "Output dir: $OUT_DIR"

echo ""
echo "Building protoc plugins..."
cd "$SCRIPT_DIR"
swift build --product protoc-gen-swift 2>&1 | tail -1
swift build --product protoc-gen-grpc-swift 2>&1 | tail -1

PLUGIN_DIR="$(swift build --show-bin-path)"
export PATH="${PLUGIN_DIR}:${PATH}"

echo "Using protoc-gen-swift: $(which protoc-gen-swift)"
echo "Using protoc-gen-grpc-swift: $(which protoc-gen-grpc-swift)"

find "$OUT_DIR" -type f -name '*.swift' -delete

echo ""
echo "Generating Swift protobuf code..."
printf '  %s\n' "${PROTOS[@]}"
protoc \
    --proto_path="$PROTO_ROOT" \
    --swift_out="$OUT_DIR" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$OUT_DIR" \
    --grpc-swift_opt=Visibility=Public \
    "${PROTOS[@]/#/$PROTO_ROOT/}"

cat > "$SOURCE_FILE" <<EOF
repository=https://github.com/ArcBoxLabs/arcbox
commit=$SOURCE_COMMIT
path=$PROTO_RELATIVE
sha256=$PROTO_SHA256
EOF

echo ""
echo "Generated files:"
find "$OUT_DIR" -type f -name '*.swift' -print | sort || echo "  (none)"
echo "Source metadata: $SOURCE_FILE"
echo ""
echo "Done."
