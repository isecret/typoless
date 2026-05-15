#!/usr/bin/env bash

set -euo pipefail

DERIVED_DATA_DIR=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/find-sparkle-root.sh [--derived-data <path>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --derived-data)
            DERIVED_DATA_DIR="$2"
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

declare -a candidates=()

if [[ -n "$DERIVED_DATA_DIR" ]]; then
    candidates+=("$DERIVED_DATA_DIR/SourcePackages/checkouts/Sparkle")
fi

candidates+=(
    "app/.derivedData/SourcePackages/checkouts/Sparkle"
)

for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate/Sparkle.xcodeproj" ]]; then
        echo "$candidate"
        exit 0
    fi
done

found_path="$(find "${DERIVED_DATA_DIR:-$HOME/Library/Developer/Xcode/DerivedData}" -path '*SourcePackages/checkouts/Sparkle/Sparkle.xcodeproj' -print -quit 2>/dev/null || true)"

if [[ -n "$found_path" ]]; then
    dirname "$found_path"
    exit 0
fi

echo "error: unable to locate Sparkle checkout" >&2
exit 1
