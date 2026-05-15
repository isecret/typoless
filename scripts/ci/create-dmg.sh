#!/usr/bin/env bash
# create-dmg.sh — 从已签名的 .app 创建并签名 DMG。

set -euo pipefail

APP_PATH=""
OUTPUT_PATH=""
VOLUME_NAME="Typoless"
SIGNING_IDENTITY=""
TIMESTAMP=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
RW_DMG_BASE="$(mktemp -u "${TMPDIR:-/tmp}/typoless-rw.XXXXXX")"
RW_DMG_PATH="${RW_DMG_BASE}.dmg"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PATH="$BACKGROUND_DIR/installer-background.png"
APP_NAME="$(basename "$APP_PATH")"
MOUNT_POINT="/Volumes/$VOLUME_NAME"
OUTPUT_BASE="${OUTPUT_PATH%.dmg}"

cleanup() {
    hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
    hdiutil detach "${MOUNT_POINT} 1" -quiet >/dev/null 2>&1 || true
    hdiutil detach "${MOUNT_POINT} 2" -quiet >/dev/null 2>&1 || true
    hdiutil detach "${MOUNT_POINT} 3" -quiet >/dev/null 2>&1 || true
    rm -rf "$STAGING_DIR"
    rm -f "$RW_DMG_PATH"
}
trap cleanup EXIT

cleanup

mkdir -p "$BACKGROUND_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
"$SCRIPT_DIR/render-dmg-background.swift" "$BACKGROUND_PATH"

rm -f "$OUTPUT_PATH"

echo "Creating writable DMG..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG_PATH"

echo "Mounting writable DMG..."
hdiutil attach "$RW_DMG_PATH" -nobrowse -quiet

echo "Configuring Finder layout..."
WINDOW_WIDTH=640
WINDOW_HEIGHT=400
osascript <<EOF
tell application "Finder"
    set screenBounds to bounds of window of desktop
    set screenLeft to item 1 of screenBounds
    set screenTop to item 2 of screenBounds
    set screenRight to item 3 of screenBounds
    set screenBottom to item 4 of screenBounds
    set windowLeft to screenLeft + ((screenRight - screenLeft - $WINDOW_WIDTH) div 2)
    set windowTop to screenTop + ((screenBottom - screenTop - $WINDOW_HEIGHT) div 2)
    set windowRight to windowLeft + $WINDOW_WIDTH
    set windowBottom to windowTop + $WINDOW_HEIGHT
    tell disk "$VOLUME_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {windowLeft, windowTop, windowRight, windowBottom}
        set zoomed of container window to false
        set sidebar width of container window to 0
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 116
        set text size of theViewOptions to 16
        set background picture of theViewOptions to file ".background:installer-background.png"
        set position of item "$APP_NAME" of container window to {170, 210}
        set position of item "Applications" of container window to {470, 210}
        close
        open
        delay 1
        set bounds of container window to {windowLeft, windowTop, windowRight, windowBottom}
        set zoomed of container window to false
        update without registering applications
        delay 1
    end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_POINT" -quiet

echo "Converting DMG..."
hdiutil convert "$RW_DMG_PATH" -ov -format UDZO -o "$OUTPUT_BASE" -quiet

if [[ -n "$SIGNING_IDENTITY" ]]; then
    CODESIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
    if [[ "$TIMESTAMP" == "1" ]]; then
        CODESIGN_ARGS+=(--timestamp)
    fi

    echo "Signing DMG..."
    codesign "${CODESIGN_ARGS[@]}" "$OUTPUT_PATH"
fi

echo "Created DMG: $OUTPUT_PATH"
