#!/usr/bin/env bash
# create-dmg.sh — 从已签名的 .app 创建并签名 DMG。

set -euo pipefail

APP_PATH=""
OUTPUT_PATH=""
VOLUME_NAME="Typoless"
SIGNING_IDENTITY=""
TIMESTAMP=0

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/create-dmg.sh \
    --app <path/to/Typoless.app> \
    --output <path/to/Typoless.dmg> \
    [--volume-name Typoless] \
    [--identity "<Developer ID Application: ...>"] \
    [--timestamp]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --volume-name)
            VOLUME_NAME="$2"
            shift 2
            ;;
        --identity)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --timestamp)
            TIMESTAMP=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$APP_PATH" || -z "$OUTPUT_PATH" ]]; then
    usage
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found: $APP_PATH" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typoless-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_PATH" "$STAGING_DIR/$(basename "$APP_PATH")"
rm -f "$OUTPUT_PATH"

echo "Creating DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_PATH"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    CODESIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
    if [[ "$TIMESTAMP" == "1" ]]; then
        CODESIGN_ARGS+=(--timestamp)
    fi

    echo "Signing DMG..."
    codesign "${CODESIGN_ARGS[@]}" "$OUTPUT_PATH"
fi

echo "Created DMG: $OUTPUT_PATH"
