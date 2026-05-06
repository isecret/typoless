#!/usr/bin/env bash
# notarize-dmg.sh — 提交 DMG 公证并在通过后 staple。

set -euo pipefail

DMG_PATH=""
KEY_PATH=""
KEY_ID=""
ISSUER_ID=""
APPLE_ID=""
TEAM_ID=""
APP_PASSWORD=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/notarize-dmg.sh \
    --dmg <path/to/Typoless.dmg> \
    [--key-path <path/to/AuthKey_xxx.p8> --key-id <apple-notary-key-id> --issuer <apple-notary-issuer-id>] \
    [--apple-id <apple-id> --team-id <team-id> --password <app-specific-password>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)
            DMG_PATH="$2"
            shift 2
            ;;
        --key-path)
            KEY_PATH="$2"
            shift 2
            ;;
        --key-id)
            KEY_ID="$2"
            shift 2
            ;;
        --issuer)
            ISSUER_ID="$2"
            shift 2
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --password)
            APP_PASSWORD="$2"
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

if [[ -z "$DMG_PATH" ]]; then
    usage
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: DMG not found: $DMG_PATH" >&2
    exit 1
fi

submit_with_api_key() {
    if [[ ! -f "$KEY_PATH" ]]; then
        echo "error: notary API key not found: $KEY_PATH" >&2
        exit 1
    fi

    echo "Submitting DMG for notarization with App Store Connect API key..."
    xcrun notarytool submit "$DMG_PATH" \
        --key "$KEY_PATH" \
        --key-id "$KEY_ID" \
        --issuer "$ISSUER_ID" \
        --wait
}

submit_with_apple_id() {
    echo "Submitting DMG for notarization with Apple ID credentials..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait
}

if [[ -n "$KEY_PATH" || -n "$KEY_ID" || -n "$ISSUER_ID" ]]; then
    if [[ -z "$KEY_PATH" || -z "$KEY_ID" || -z "$ISSUER_ID" ]]; then
        echo "error: --key-path, --key-id, and --issuer must be provided together" >&2
        exit 1
    fi
    submit_with_api_key
elif [[ -n "$APPLE_ID" || -n "$TEAM_ID" || -n "$APP_PASSWORD" ]]; then
    if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_PASSWORD" ]]; then
        echo "error: --apple-id, --team-id, and --password must be provided together" >&2
        exit 1
    fi
    submit_with_apple_id
else
    echo "error: no notarization credentials provided" >&2
    usage
    exit 1
fi

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "Validating stapled DMG..."
xcrun stapler validate "$DMG_PATH"
