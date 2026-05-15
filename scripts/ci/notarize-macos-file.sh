#!/usr/bin/env bash

set -euo pipefail

FILE_PATH=""
STAPLE_PATH=""
KEY_PATH=""
KEY_ID=""
ISSUER_ID=""
APPLE_ID=""
TEAM_ID=""
APP_PASSWORD=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/notarize-macos-file.sh \
    --file <path> \
    [--staple <path>] \
    [--key-path <path/to/AuthKey_xxx.p8> --key-id <apple-notary-key-id> --issuer <apple-notary-issuer-id>] \
    [--apple-id <apple-id> --team-id <team-id> --password <app-specific-password>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            FILE_PATH="$2"
            shift 2
            ;;
        --staple)
            STAPLE_PATH="$2"
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

if [[ -z "$FILE_PATH" ]]; then
    usage
    exit 1
fi

if [[ ! -e "$FILE_PATH" ]]; then
    echo "error: file not found: $FILE_PATH" >&2
    exit 1
fi

if [[ -n "$STAPLE_PATH" && ! -e "$STAPLE_PATH" ]]; then
    echo "error: staple target not found: $STAPLE_PATH" >&2
    exit 1
fi

submit_with_api_key() {
    if [[ ! -f "$KEY_PATH" ]]; then
        echo "error: notary API key not found: $KEY_PATH" >&2
        exit 1
    fi

    xcrun notarytool submit "$FILE_PATH" \
        --key "$KEY_PATH" \
        --key-id "$KEY_ID" \
        --issuer "$ISSUER_ID" \
        --wait
}

submit_with_apple_id() {
    xcrun notarytool submit "$FILE_PATH" \
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

if [[ -n "$STAPLE_PATH" ]]; then
    echo "Stapling notarization ticket to $STAPLE_PATH..."
    xcrun stapler staple "$STAPLE_PATH"
    xcrun stapler validate "$STAPLE_PATH"
fi
