#!/usr/bin/env bash

set -euo pipefail

APP_PATH=""
OUTPUT_PATH=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/create-sparkle-archive.sh \
    --app <path/to/Typoless.app> \
    --output <path/to/Typoless.zip>
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
rm -f "$OUTPUT_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_PATH"

echo "Created Sparkle archive: $OUTPUT_PATH"
