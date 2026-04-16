#!/usr/bin/env bash
#
# Generate Kotlin bindings from codex-mobile-client.
#
# Usage:  ./generate-bindings.sh [--release]
#
# Outputs:
#   generated/kotlin/  — Kotlin source files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR"
source "$WORKSPACE_DIR/../../tools/scripts/load-sccache-aws-creds.sh"
OUT_KOTLIN="$WORKSPACE_DIR/generated/kotlin"

cd "$WORKSPACE_DIR"

if [[ -z "${RUSTC_WRAPPER:-}" ]] && command -v sccache >/dev/null 2>&1; then
    export RUSTC_WRAPPER="$(command -v sccache)"
fi

PROFILE="debug"

for arg in "$@"; do
    case "$arg" in
        --release)
            PROFILE="release"
            ;;
        *)
            echo "usage: $(basename "$0") [--release]" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# 1. Build the cdylib so uniffi-bindgen can read its metadata
# ---------------------------------------------------------------------------
echo "==> Building codex-mobile-client cdylib ($PROFILE)..."

if [[ "$PROFILE" == "release" ]]; then
    cargo build -p codex-mobile-client --release
else
    cargo build -p codex-mobile-client
fi

DYLIB_PATH="$WORKSPACE_DIR/target/$PROFILE"

if [[ "$(uname)" == "Darwin" ]]; then
    DYLIB_FILE="$DYLIB_PATH/libcodex_mobile_client.dylib"
else
    DYLIB_FILE="$DYLIB_PATH/libcodex_mobile_client.so"
fi

if [[ ! -f "$DYLIB_FILE" ]]; then
    echo "ERROR: Could not find built library at $DYLIB_FILE" >&2
    exit 1
fi

echo "==> Generating Kotlin bindings -> $OUT_KOTLIN"
mkdir -p "$OUT_KOTLIN"
rm -rf \
    "$OUT_KOTLIN/uniffi/codex_app_server_protocol" \
    "$OUT_KOTLIN/uniffi/codex_protocol"
cargo run -p uniffi-bindgen -- generate \
    --library "$DYLIB_FILE" \
    --language kotlin \
    --out-dir "$OUT_KOTLIN"

echo "==> Done. Generated bindings:"
find "$OUT_KOTLIN" -type f | sort
