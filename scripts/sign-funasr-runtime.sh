#!/usr/bin/env bash
# sign-funasr-runtime.sh — Sign all Mach-O binaries in the FunASR bundle.
#
# Usage:
#   ./scripts/sign-funasr-runtime.sh [--identity <id>] [--bundle-dir <dir>]
#
# Environment variables:
#   SIGNING_IDENTITY    Code signing identity (default: "-" for ad-hoc)
#   BUNDLE_DIR          FunASR bundle directory to sign
#   ENTITLEMENTS        Path to entitlements plist (optional)
#
# This script finds and signs all Mach-O executables, .dylib, and .so files
# within the FunASR runtime bundle. It must be run BEFORE the final App
# bundle signing to avoid nested signature conflicts.
#
# Prerequisites:
#   - macOS with Xcode Command Line Tools
#   - Valid signing identity (or use "-" for ad-hoc during development)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
BUNDLE_DIR="${BUNDLE_DIR:-$PROJECT_ROOT/build/funasr-bundle}"
ENTITLEMENTS="${ENTITLEMENTS:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        --bundle-dir)
            BUNDLE_DIR="$2"
            shift 2
            ;;
        --entitlements)
            ENTITLEMENTS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "ERROR: Bundle directory not found: $BUNDLE_DIR"
    echo "       Run ./scripts/bundle-funasr-runtime.sh first."
    exit 1
fi

echo "==> FunASR Runtime Signing"
echo "    Bundle:   $BUNDLE_DIR"
echo "    Identity: $SIGNING_IDENTITY"
if [[ -n "$ENTITLEMENTS" ]]; then
    echo "    Entitlements: $ENTITLEMENTS"
fi
echo ""

# Build codesign arguments
CODESIGN_ARGS=(--force --options runtime --sign "$SIGNING_IDENTITY")
if [[ -n "$ENTITLEMENTS" ]]; then
    CODESIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
fi

# Find all Mach-O files (executables, .dylib, .so)
SIGNED_COUNT=0
FAILED_COUNT=0

sign_file() {
    local file="$1"
    local rel_path="${file#$BUNDLE_DIR/}"

    if codesign "${CODESIGN_ARGS[@]}" "$file" 2>/dev/null; then
        ((SIGNED_COUNT++))
    else
        echo "    FAILED: $rel_path"
        ((FAILED_COUNT++))
    fi
}

echo "[1/3] Signing Python runtime executable..."
PYTHON_BIN="$BUNDLE_DIR/runtime/python3"
if [[ -f "$PYTHON_BIN" ]]; then
    sign_file "$PYTHON_BIN"
    echo "    ✓ runtime/python3"
else
    echo "    WARNING: Python binary not found at $PYTHON_BIN"
fi

echo "[2/3] Signing dynamic libraries (.dylib)..."
while IFS= read -r -d '' file; do
    sign_file "$file"
done < <(find "$BUNDLE_DIR" -name "*.dylib" -print0 2>/dev/null)
echo "    ✓ Signed $SIGNED_COUNT .dylib files"

DYLIB_COUNT=$SIGNED_COUNT
SIGNED_COUNT=0

echo "[3/3] Signing Python extension modules (.so)..."
while IFS= read -r -d '' file; do
    sign_file "$file"
done < <(find "$BUNDLE_DIR" -name "*.so" -print0 2>/dev/null)
echo "    ✓ Signed $SIGNED_COUNT .so files"

SO_COUNT=$SIGNED_COUNT
TOTAL=$((DYLIB_COUNT + SO_COUNT + 1))

echo ""

# Verify
echo "==> Verifying signatures..."
VERIFY_FAILED=0
while IFS= read -r -d '' file; do
    if ! codesign --verify --strict "$file" 2>/dev/null; then
        echo "    VERIFY FAILED: ${file#$BUNDLE_DIR/}"
        ((VERIFY_FAILED++))
    fi
done < <(find "$BUNDLE_DIR" \( -name "*.dylib" -o -name "*.so" -o -name "python3" \) -print0 2>/dev/null)

echo ""
if [[ $VERIFY_FAILED -eq 0 && $FAILED_COUNT -eq 0 ]]; then
    echo "==> All $TOTAL files signed and verified successfully."
    echo ""
    echo "Next steps:"
    echo "  1. Copy $BUNDLE_DIR to App bundle: Contents/Resources/funasr/"
    echo "  2. Sign the App bundle: codesign --deep --force --options runtime --sign \"\$IDENTITY\" Typoless.app"
    echo "  3. Notarize: xcrun notarytool submit Typoless.zip --apple-id ... --team-id ..."
    echo "  4. Staple: xcrun stapler staple Typoless.app"
else
    echo "==> ERRORS: $FAILED_COUNT signing failures, $VERIFY_FAILED verification failures."
    exit 1
fi
