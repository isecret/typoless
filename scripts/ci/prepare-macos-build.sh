#!/usr/bin/env bash
# prepare-macos-build.sh — CI 构建前置准备
#
# 职责:
#   1. 确保 xcodegen 可用
#   2. 准备 RNNoise 动态库（优先使用仓库资源，缺失时源码编译）
#   3. 生成 Xcode 工程
#
# 用法:
#   ./scripts/ci/prepare-macos-build.sh
#
# 环境变量:
#   SKIP_RNNOISE    设为 1 可跳过 RNNoise 准备（适用于已有资源的场景）
#   RNNOISE_GIT_REF RNNoise 拉取版本，默认 v0.2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_DIR="${PROJECT_ROOT}/app"

echo "=== Typoless CI 构建准备 ==="
echo "  Project root: ${PROJECT_ROOT}"
echo ""

# --- 1. 确保 xcodegen 可用 ---
echo "--- Step 1: 检查 xcodegen ---"
if command -v xcodegen &>/dev/null; then
    echo "  ✓ xcodegen already installed: $(xcodegen --version 2>&1 | head -1)"
else
    echo "  → Installing xcodegen via Homebrew..."
    brew install xcodegen
    echo "  ✓ xcodegen installed: $(xcodegen --version 2>&1 | head -1)"
fi
echo ""

# --- 2. 准备 RNNoise ---
echo "--- Step 2: 准备 RNNoise 资源 ---"
RNNOISE_RESOURCE_DIR="${APP_DIR}/Typoless/Resources/rnnoise/lib"
RNNOISE_GIT_REF="${RNNOISE_GIT_REF:-v0.2}"

if [ "${SKIP_RNNOISE:-0}" = "1" ]; then
    echo "  → SKIP_RNNOISE=1, skipping RNNoise setup"
elif [ -f "${RNNOISE_RESOURCE_DIR}/librnnoise.dylib" ]; then
    echo "  ✓ RNNoise 已存在，跳过"
else
    echo "  → RNNoise 资源缺失，开始源码编译..."
    BUILD_ROOT="${PROJECT_ROOT}/build/ci-rnnoise"
    SRC_DIR="${BUILD_ROOT}/rnnoise-src"
    rm -rf "${BUILD_ROOT}"
    mkdir -p "${BUILD_ROOT}"

    git clone --depth 1 --branch "${RNNOISE_GIT_REF}" https://github.com/xiph/rnnoise.git "${SRC_DIR}"
    cd "${SRC_DIR}"
    ./autogen.sh
    ./configure
    make -j"$(sysctl -n hw.ncpu)"

    RNNOISE_LIB="${SRC_DIR}/.libs/librnnoise.dylib"
    if [ ! -f "${RNNOISE_LIB}" ]; then
        echo "  error: 源码编译完成后仍未找到 librnnoise.dylib"
        exit 1
    fi

    mkdir -p "${RNNOISE_RESOURCE_DIR}"
    cp "${RNNOISE_LIB}" "${RNNOISE_RESOURCE_DIR}/librnnoise.dylib"
    echo "  ✓ RNNoise 已编译并复制到 Resources"
fi
echo ""

# --- 3. 生成 Xcode 工程 ---
echo "--- Step 3: 生成 Xcode 工程 ---"
cd "${APP_DIR}"
xcodegen generate
echo "  ✓ Typoless.xcodeproj 已生成"
echo ""

echo "=== 构建准备完成 ✓ ==="
