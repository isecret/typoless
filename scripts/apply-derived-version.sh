#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FALLBACK_VERSION="${MARKETING_VERSION:-}"
PLIST_PATH=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/apply-derived-version.sh [--plist <path>] [--fallback <version>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plist)
            PLIST_PATH="${2:-}"
            shift 2
            ;;
        --fallback)
            FALLBACK_VERSION="${2:-}"
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

if [[ -z "${PLIST_PATH}" ]]; then
    if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${INFOPLIST_PATH:-}" ]]; then
        echo "error: missing --plist and no Xcode build environment found" >&2
        exit 1
    fi
    PLIST_PATH="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
fi

if [[ ! -f "${PLIST_PATH}" ]]; then
    echo "error: Info.plist not found at ${PLIST_PATH}" >&2
    exit 1
fi

VERSION="$("${PROJECT_ROOT}/scripts/ci/version-from-tag.sh" --fallback "${FALLBACK_VERSION}")"

for key in CFBundleShortVersionString CFBundleVersion; do
    /usr/libexec/PlistBuddy -c "Set :${key} ${VERSION}" "${PLIST_PATH}" >/dev/null 2>&1 || \
        /usr/libexec/PlistBuddy -c "Add :${key} string ${VERSION}" "${PLIST_PATH}" >/dev/null
done

echo "Applied derived version ${VERSION} to ${PLIST_PATH}"
