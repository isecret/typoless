#!/usr/bin/env bash
# bundle-funasr-runtime.sh — Package FunASR Python runtime into App bundle.
#
# This script downloads a standalone Python runtime, installs locked
# dependencies, and prepares the bundle-ready directory structure.
#
# Usage:
#   ./scripts/bundle-funasr-runtime.sh [--output <dir>]
#
# Environment variables:
#   PYTHON_STANDALONE_VERSION   Python version (default: 3.11.11)
#   PYTHON_STANDALONE_DATE      Release date tag (default: 20241206)
#   TARGET_ARCH                 Target architecture (default: aarch64)
#   OUTPUT_DIR                  Output directory override
#
# Prerequisites:
#   - curl, tar, rsync
#   - Internet access for initial download
#
# Output structure:
#   <output>/
#   ├── runtime/
#   │   ├── python3              # Standalone Python interpreter
#   │   └── lib/                 # Python stdlib + site-packages
#   ├── worker/
#   │   ├── funasr_worker.py
#   │   └── requirements-lock.txt
#   └── manifest.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
PYTHON_VERSION="${PYTHON_STANDALONE_VERSION:-3.11.11}"
PYTHON_DATE="${PYTHON_STANDALONE_DATE:-20241206}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build/funasr-bundle}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

FUNASR_RESOURCE="$PROJECT_ROOT/app/Typoless/Resources/funasr"
REQUIREMENTS_LOCK="$FUNASR_RESOURCE/worker/requirements-lock.txt"

# python-build-standalone download URL pattern
PYTHON_TARBALL="cpython-${PYTHON_VERSION}+${PYTHON_DATE}-${TARGET_ARCH}-apple-darwin-install_only_stripped.tar.gz"
PYTHON_URL="https://github.com/indygreg/python-build-standalone/releases/download/${PYTHON_DATE}/${PYTHON_TARBALL}"

CACHE_DIR="$PROJECT_ROOT/build/cache"
PYTHON_CACHE="$CACHE_DIR/$PYTHON_TARBALL"

echo "==> FunASR Runtime Bundling"
echo "    Python: ${PYTHON_VERSION} (${TARGET_ARCH})"
echo "    Output: ${OUTPUT_DIR}"
echo ""

# Step 1: Download Python standalone runtime
echo "[1/5] Downloading Python standalone runtime..."
mkdir -p "$CACHE_DIR"
if [[ ! -f "$PYTHON_CACHE" ]]; then
    echo "    Downloading from: $PYTHON_URL"
    curl -L --progress-bar -o "$PYTHON_CACHE" "$PYTHON_URL"
else
    echo "    Using cached: $PYTHON_CACHE"
fi

# Step 2: Extract runtime
echo "[2/5] Extracting Python runtime..."
EXTRACT_DIR="$PROJECT_ROOT/build/python-extract"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$PYTHON_CACHE" -C "$EXTRACT_DIR"

# The extracted structure is: python/bin/python3, python/lib/...
PYTHON_ROOT="$EXTRACT_DIR/python"
PYTHON_BIN="$PYTHON_ROOT/bin/python3"

if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "ERROR: Python binary not found at $PYTHON_BIN"
    exit 1
fi

echo "    Python version: $("$PYTHON_BIN" --version 2>&1)"

# Step 3: Install locked dependencies
echo "[3/5] Installing Python dependencies (arm64 only-binary)..."
"$PYTHON_BIN" -m pip install \
    --quiet \
    --no-cache-dir \
    --only-binary :all: \
    --target "$PYTHON_ROOT/lib/python${PYTHON_VERSION%.*}/site-packages" \
    -r "$REQUIREMENTS_LOCK"

# Step 4: Assemble output directory
echo "[4/5] Assembling bundle structure..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/runtime" "$OUTPUT_DIR/worker"

# Copy Python runtime
cp "$PYTHON_BIN" "$OUTPUT_DIR/runtime/python3"
rsync -a "$PYTHON_ROOT/lib/" "$OUTPUT_DIR/runtime/lib/"

# Copy worker files
cp "$FUNASR_RESOURCE/worker/funasr_worker.py" "$OUTPUT_DIR/worker/"
cp "$REQUIREMENTS_LOCK" "$OUTPUT_DIR/worker/"

# Copy manifest
if [[ -f "$FUNASR_RESOURCE/manifest.json" ]]; then
    cp "$FUNASR_RESOURCE/manifest.json" "$OUTPUT_DIR/"
fi

# Step 5: Clean up unnecessary files
echo "[5/5] Cleaning up unnecessary files..."
find "$OUTPUT_DIR/runtime" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT_DIR/runtime" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT_DIR/runtime" -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT_DIR/runtime" -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
find "$OUTPUT_DIR/runtime" -name "*.pyc" -delete 2>/dev/null || true
find "$OUTPUT_DIR/runtime" -name "*.pyo" -delete 2>/dev/null || true
find "$OUTPUT_DIR/runtime" -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true

# Report size
BUNDLE_SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
echo ""
echo "==> Bundle ready: $OUTPUT_DIR ($BUNDLE_SIZE)"
echo "    Runtime: $OUTPUT_DIR/runtime/python3"
echo "    Worker:  $OUTPUT_DIR/worker/funasr_worker.py"
echo ""
echo "Next step: run ./scripts/sign-funasr-runtime.sh to sign all binaries."
