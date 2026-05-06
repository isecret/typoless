#!/usr/bin/env bash
# verify-macos-release.sh — 校验已签名、公证的 macOS 发布产物。

set -euo pipefail

APP_PATH=""
DMG_PATH=""
TEAM_ID=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/verify-macos-release.sh \
    --app <path/to/Typoless.app> \
    --dmg <path/to/Typoless.dmg> \
    [--team-id <TEAMID>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="$2"
            shift 2
            ;;
        --dmg)
            DMG_PATH="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
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

if [[ -z "$APP_PATH" || -z "$DMG_PATH" ]]; then
    usage
    exit 1
fi

echo "Verifying app signature..."
codesign --verify --deep --strict "$APP_PATH"

echo "Verifying DMG signature..."
codesign --verify --strict "$DMG_PATH"

echo "Validating stapled DMG..."
xcrun stapler validate "$DMG_PATH"

echo "Assessing DMG with spctl..."
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/typoless-dmg-mount.XXXXXX")"
cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    rm -rf "$MOUNT_POINT"
}
trap cleanup EXIT

echo "Mounting DMG for app assessment..."
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet

MOUNTED_APP_PATH="$MOUNT_POINT/$(basename "$APP_PATH")"
if [[ ! -d "$MOUNTED_APP_PATH" ]]; then
    echo "error: mounted app not found: $MOUNTED_APP_PATH" >&2
    exit 1
fi

echo "Assessing mounted app with spctl..."
spctl --assess --type execute --verbose "$MOUNTED_APP_PATH"

if [[ -n "$TEAM_ID" ]]; then
    echo "Checking TeamIdentifier..."
    codesign -dvv "$APP_PATH" 2>&1 | grep -F "TeamIdentifier=$TEAM_ID" >/dev/null
    codesign -dvv "$DMG_PATH" 2>&1 | grep -F "TeamIdentifier=$TEAM_ID" >/dev/null
fi

echo "Release artifacts verified."
