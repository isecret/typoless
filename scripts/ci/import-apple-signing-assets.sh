#!/usr/bin/env bash
# import-apple-signing-assets.sh — 导入 Developer ID 证书，并按需准备 notary API key。

set -euo pipefail

WORKSPACE_DIR=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/import-apple-signing-assets.sh [--workspace-dir <dir>]

Required env:
  APPLE_DEVELOPER_ID_APP_CERT_BASE64
  APPLE_DEVELOPER_ID_APP_CERT_PASSWORD

Optional env:
  APPLE_SIGNING_IDENTITY
  APPLE_NOTARY_API_KEY_BASE64
  APPLE_NOTARY_KEY_ID
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-dir)
            WORKSPACE_DIR="$2"
            shift 2
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

required_envs=(
    APPLE_DEVELOPER_ID_APP_CERT_BASE64
    APPLE_DEVELOPER_ID_APP_CERT_PASSWORD
)

for name in "${required_envs[@]}"; do
    if [[ -z "${!name:-}" ]]; then
        echo "error: missing required environment variable: ${name}" >&2
        exit 1
    fi
done

if [[ -z "$WORKSPACE_DIR" ]]; then
    RUNNER_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    WORKSPACE_DIR="${RUNNER_ROOT%/}/typoless-signing"
fi

mkdir -p "$WORKSPACE_DIR"

CERT_PATH="$WORKSPACE_DIR/developer-id-application.p12"
KEYCHAIN_PATH="$WORKSPACE_DIR/typoless-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
NOTARY_KEY_PATH=""

printf '%s' "$APPLE_DEVELOPER_ID_APP_CERT_BASE64" | base64 -d > "$CERT_PATH"
chmod 600 "$CERT_PATH"

if [[ -n "${APPLE_NOTARY_API_KEY_BASE64:-}" || -n "${APPLE_NOTARY_KEY_ID:-}" ]]; then
    if [[ -z "${APPLE_NOTARY_API_KEY_BASE64:-}" || -z "${APPLE_NOTARY_KEY_ID:-}" ]]; then
        echo "error: APPLE_NOTARY_API_KEY_BASE64 and APPLE_NOTARY_KEY_ID must be provided together" >&2
        exit 1
    fi

    NOTARY_KEY_PATH="$WORKSPACE_DIR/AuthKey_${APPLE_NOTARY_KEY_ID}.p8"
    printf '%s' "$APPLE_NOTARY_API_KEY_BASE64" | base64 -d > "$NOTARY_KEY_PATH"
    chmod 600 "$NOTARY_KEY_PATH"
fi

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security default-keychain -s "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH"

security import "$CERT_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "$APPLE_DEVELOPER_ID_APP_CERT_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH"

if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
    if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "$APPLE_SIGNING_IDENTITY" >/dev/null; then
        echo "error: imported certificate does not expose signing identity: $APPLE_SIGNING_IDENTITY" >&2
        security find-identity -v -p codesigning "$KEYCHAIN_PATH" >&2 || true
        exit 1
    fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "workspace-dir=$WORKSPACE_DIR"
        echo "keychain-path=$KEYCHAIN_PATH"
        echo "keychain-password=$KEYCHAIN_PASSWORD"
        echo "notary-key-path=$NOTARY_KEY_PATH"
    } >> "$GITHUB_OUTPUT"
fi

echo "Imported Apple signing assets into temporary keychain."
