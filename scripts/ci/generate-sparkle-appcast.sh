#!/usr/bin/env bash

set -euo pipefail

ARCHIVE_DIR=""
OUTPUT_PATH=""
DOWNLOAD_URL_PREFIX=""
PRIVATE_KEY_FILE=""
SPARKLE_ROOT=""
DERIVED_DATA_DIR=""
FULL_RELEASE_NOTES_URL=""
PRODUCT_LINK=""
TOOL_DERIVED_DATA=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/generate-sparkle-appcast.sh \
    --archive-dir <directory> \
    --output <path/to/appcast.xml> \
    --download-url-prefix <url> \
    --private-key-file <path/to/private-key> \
    [--sparkle-root <path/to/Sparkle>] \
    [--derived-data <path/to/xcode-derived-data>] \
    [--full-release-notes-url <url>] \
    [--link <url>] \
    [--tool-derived-data <path>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive-dir)
            ARCHIVE_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --download-url-prefix)
            DOWNLOAD_URL_PREFIX="$2"
            shift 2
            ;;
        --private-key-file)
            PRIVATE_KEY_FILE="$2"
            shift 2
            ;;
        --sparkle-root)
            SPARKLE_ROOT="$2"
            shift 2
            ;;
        --derived-data)
            DERIVED_DATA_DIR="$2"
            shift 2
            ;;
        --full-release-notes-url)
            FULL_RELEASE_NOTES_URL="$2"
            shift 2
            ;;
        --link)
            PRODUCT_LINK="$2"
            shift 2
            ;;
        --tool-derived-data)
            TOOL_DERIVED_DATA="$2"
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

if [[ -z "$ARCHIVE_DIR" || -z "$OUTPUT_PATH" || -z "$DOWNLOAD_URL_PREFIX" || -z "$PRIVATE_KEY_FILE" ]]; then
    usage
    exit 1
fi

case "$DOWNLOAD_URL_PREFIX" in
    */) ;;
    *) DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX}/" ;;
esac

if [[ ! -d "$ARCHIVE_DIR" ]]; then
    echo "error: archive directory not found: $ARCHIVE_DIR" >&2
    exit 1
fi

if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
    echo "error: private key file not found: $PRIVATE_KEY_FILE" >&2
    exit 1
fi

if [[ -z "$SPARKLE_ROOT" ]]; then
    find_args=()
    if [[ -n "$DERIVED_DATA_DIR" ]]; then
        find_args=(--derived-data "$DERIVED_DATA_DIR")
    fi
    SPARKLE_ROOT="$(./scripts/ci/find-sparkle-root.sh "${find_args[@]}")"
fi

if [[ ! -d "$SPARKLE_ROOT/Sparkle.xcodeproj" ]]; then
    echo "error: Sparkle checkout is invalid: $SPARKLE_ROOT" >&2
    exit 1
fi

if [[ -z "$TOOL_DERIVED_DATA" ]]; then
    TOOL_DERIVED_DATA="${TMPDIR:-/tmp}/typoless-sparkle-tools"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

# Sparkle generate_appcast treats an existing output file as an existing feed to
# merge into. CI commonly provisions the target path via mktemp, which creates
# a zero-length placeholder file that is not valid XML.
if [[ -f "$OUTPUT_PATH" && ! -s "$OUTPUT_PATH" ]]; then
    rm -f "$OUTPUT_PATH"
fi

echo "Building Sparkle generate_appcast tool..."
xcodebuild \
    -project "$SPARKLE_ROOT/Sparkle.xcodeproj" \
    -scheme generate_appcast \
    -configuration Release \
    -derivedDataPath "$TOOL_DERIVED_DATA" \
    build >/dev/null

TOOL_BINARY="$TOOL_DERIVED_DATA/Build/Products/Release/generate_appcast"

if [[ ! -x "$TOOL_BINARY" ]]; then
    echo "error: generate_appcast tool not found: $TOOL_BINARY" >&2
    exit 1
fi

cmd=(
    "$TOOL_BINARY"
    --ed-key-file "$PRIVATE_KEY_FILE"
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --maximum-versions 1
    --maximum-deltas 0
    -o "$OUTPUT_PATH"
)

if [[ -n "$FULL_RELEASE_NOTES_URL" ]]; then
    cmd+=(--full-release-notes-url "$FULL_RELEASE_NOTES_URL")
fi

if [[ -n "$PRODUCT_LINK" ]]; then
    cmd+=(--link "$PRODUCT_LINK")
fi

cmd+=("$ARCHIVE_DIR")

"${cmd[@]}"

if command -v rg >/dev/null 2>&1; then
    has_item_command=(rg -q "<item>" "$OUTPUT_PATH")
else
    has_item_command=(grep -q "<item>" "$OUTPUT_PATH")
fi

if ! "${has_item_command[@]}"; then
    echo "error: generated appcast does not contain any update items: $OUTPUT_PATH" >&2
    exit 1
fi

echo "Generated Sparkle appcast: $OUTPUT_PATH"
