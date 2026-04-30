#!/usr/bin/env bash
# prepare-macos-build.sh — CI 构建前置准备
#
# 职责:
#   1. 确保 xcodegen 可用
#   2. 准备 RNNoise 动态库（Homebrew 安装并复制到 Resources）
#   3. 生成 Xcode 工程
#
# 用法:
#   ./scripts/ci/prepare-macos-build.sh
#
# 环境变量:
#   SKIP_RNNOISE    设为 1 可跳过 RNNoise 准备（适用于已有资源的场景）

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

if [ "${SKIP_RNNOISE:-0}" = "1" ]; then
    echo "  → SKIP_RNNOISE=1, skipping RNNoise setup"
elif [ -f "${RNNOISE_RESOURCE_DIR}/librnnoise.dylib" ]; then
    echo "  ✓ RNNoise 已存在，跳过"
else
    echo "  → Installing RNNoise via Homebrew..."
    brew install rnnoise

    BREW_PREFIX="$(brew --prefix)"
    RNNOISE_LIB="${BREW_PREFIX}/lib/librnnoise.dylib"

    if [ ! -f "${RNNOISE_LIB}" ]; then
        echo "  error: librnnoise.dylib not found at ${RNNOISE_LIB}"
        exit 1
    fi

    mkdir -p "${RNNOISE_RESOURCE_DIR}"
    cp "${RNNOISE_LIB}" "${RNNOISE_RESOURCE_DIR}/librnnoise.dylib"
    echo "  ✓ RNNoise 已复制到 Resources"
fi
echo ""

# --- 3. 生成 Xcode 工程 ---
echo "--- Step 3: 生成 Xcode 工程 ---"
cd "${APP_DIR}"
xcodegen generate
echo "  ✓ Typoless.xcodeproj 已生成"
echo ""

echo "=== 构建准备完成 ✓ ==="
