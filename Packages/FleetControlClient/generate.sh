#!/bin/bash
# Generate Swift protobuf and gRPC code from the fleet agent local control API.
#
# Prerequisites:
#   brew install protobuf
#
# Usage:
#   cd Packages/FleetControlClient && ./generate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/Sources/FleetControlClient/Generated"
PROTO_ROOT=""

PROTOS=(
    "arcbox/fleet/control/v1/control.proto"
)

find_local_proto() {
    local candidates=(
        "${SCRIPT_DIR}/../../../arcbox/fleet/arcbox-fleet-control-proto/proto"
    )
    for dir in "${candidates[@]}"; do
        if [ -d "$dir" ]; then
            echo "$(cd "$dir" && pwd)"
            return 0
        fi
    done
    return 1
}

PROTO_ROOT="$(find_local_proto)" || {
    echo "Error: local fleet control proto directory not found" >&2
    echo "Expected sibling checkout at ../../../arcbox/fleet/arcbox-fleet-control-proto/proto" >&2
    exit 1
}

mkdir -p "$OUT_DIR"

echo "Using local fleet control proto: $PROTO_ROOT"
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

echo ""
echo "Generated files:"
find "$OUT_DIR" -type f -name '*.swift' -print | sort || echo "  (none)"
echo ""
echo "Done."
