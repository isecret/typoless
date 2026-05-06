#!/usr/bin/env bash
# sign-macos-app.sh — 对归档产物中的 Typoless.app 进行正式签名。

set -euo pipefail

APP_PATH=""
SIGNING_IDENTITY=""
ENTITLEMENTS=""
TIMESTAMP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/sign-macos-app.sh \
    --app <path/to/Typoless.app> \
    --identity "<Developer ID Application: ...>" \
    --entitlements <path/to/Typoless.entitlements> \
    [--timestamp]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="$2"
            shift 2
            ;;
        --identity)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --entitlements)
            ENTITLEMENTS="$2"
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

if [[ -z "$APP_PATH" || -z "$SIGNING_IDENTITY" || -z "$ENTITLEMENTS" ]]; then
    usage
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found: $APP_PATH" >&2
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "error: entitlements file not found: $ENTITLEMENTS" >&2
    exit 1
fi

CODESIGN_ARGS=(--force --options runtime --sign "$SIGNING_IDENTITY")
if [[ "$TIMESTAMP" == "1" ]]; then
    CODESIGN_ARGS+=(--timestamp)
fi

FUNASR_ROOT="$APP_PATH/Contents/Resources/funasr"
if [[ -d "$FUNASR_ROOT" ]]; then
    RUNTIME_SIGN_ARGS=(
        --bundle-dir "$FUNASR_ROOT"
        --identity "$SIGNING_IDENTITY"
    )
    if [[ "$TIMESTAMP" == "1" ]]; then
        RUNTIME_SIGN_ARGS+=(--timestamp)
    fi

    "$PROJECT_ROOT/scripts/sign-funasr-runtime.sh" \
        "${RUNTIME_SIGN_ARGS[@]}"
fi

RNNOISE_LIB="$APP_PATH/Contents/Resources/rnnoise/lib/librnnoise.dylib"
if [[ -f "$RNNOISE_LIB" ]]; then
    echo "Signing RNNoise dylib..."
    codesign "${CODESIGN_ARGS[@]}" "$RNNOISE_LIB"
fi

echo "Signing app bundle..."
codesign \
    "${CODESIGN_ARGS[@]}" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"

echo "Verifying signed app bundle..."
codesign --verify --deep --strict "$APP_PATH"

echo "Signed app: $APP_PATH"
