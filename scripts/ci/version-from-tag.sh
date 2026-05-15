#!/usr/bin/env bash

set -euo pipefail

TAG=""
FALLBACK_VERSION=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/ci/version-from-tag.sh [<tag>]
  ./scripts/ci/version-from-tag.sh --tag <tag>
  ./scripts/ci/version-from-tag.sh --fallback <version>

Behavior:
  - If a tag is provided, parse vX.Y.Z -> X.Y.Z strictly.
  - Otherwise, try to derive the nearest reachable git tag matching v*.
  - If no git tag is available, return --fallback <version>.
EOF
}

normalize_version() {
    local raw_version="${1:-}"
    if [[ "${raw_version}" =~ ^v([0-9]+(\.[0-9]+)*)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "${raw_version}" =~ ^([0-9]+(\.[0-9]+)*)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            TAG="${2:-}"
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
            if [[ -z "${TAG}" ]]; then
                TAG="$1"
                shift
            else
                echo "error: unexpected argument '$1'" >&2
                usage
                exit 1
            fi
            ;;
    esac
done

if [[ -n "${TAG}" ]]; then
    if ! version="$(normalize_version "${TAG}")"; then
        echo "error: expected release tag in format v<version>, got '${TAG}'" >&2
        exit 1
    fi
    echo "${version}"
    exit 0
fi

if git_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)"; then
    if version="$(normalize_version "${git_tag}")"; then
        echo "${version}"
        exit 0
    fi
fi

if [[ -n "${FALLBACK_VERSION}" ]]; then
    if version="$(normalize_version "${FALLBACK_VERSION}")"; then
        echo "${version}"
        exit 0
    fi

    echo "error: fallback version must be in format X.Y.Z, got '${FALLBACK_VERSION}'" >&2
    exit 1
fi

echo "error: no matching git tag found and no fallback version provided" >&2
exit 1
