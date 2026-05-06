#!/usr/bin/env bash
# prepare-macos-build.sh — CI 构建前置准备
#
# 职责:
#   1. 确保 xcodegen 可用
#   2. 在正式发布模式下校验签名/公证依赖
#   3. 校验仓库内 RNNoise 动态库是否就绪
#   4. 生成 Xcode 工程
#
# 用法:
#   ./scripts/ci/prepare-macos-build.sh
#
# 环境变量:
#   SKIP_RNNOISE    设为 1 可跳过 RNNoise 校验（适用于特殊调试场景）
#   RELEASE_BUILD   设为 1 时额外校验签名/公证所需工具

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

# --- 2. 正式发布依赖检查 ---
echo "--- Step 2: 检查正式发布依赖 ---"
if [ "${RELEASE_BUILD:-0}" = "1" ]; then
    REQUIRED_TOOLS=(codesign security hdiutil xcrun)
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            echo "  error: release build requires '${tool}', but it is not available"
            exit 1
        fi
    done

    if ! xcrun notarytool --help >/dev/null 2>&1; then
        echo "  error: xcrun notarytool is not available on this runner"
        exit 1
    fi

    if [ ! -f "${APP_DIR}/Typoless/Typoless.entitlements" ]; then
        echo "  error: missing app entitlements file: ${APP_DIR}/Typoless/Typoless.entitlements"
        exit 1
    fi

    echo "  ✓ Release signing/notarization tools are available"
else
    echo "  → RELEASE_BUILD not enabled, skipping release-only checks"
fi
echo ""

# --- 3. 准备 RNNoise ---
echo "--- Step 3: 准备 RNNoise 资源 ---"
RNNOISE_RESOURCE_DIR="${APP_DIR}/Typoless/Resources/rnnoise/lib"

if [ "${SKIP_RNNOISE:-0}" = "1" ]; then
    echo "  → SKIP_RNNOISE=1, skipping RNNoise setup"
elif [ -f "${RNNOISE_RESOURCE_DIR}/librnnoise.dylib" ]; then
    echo "  ✓ RNNoise 已存在，跳过"
else
    echo "  error: RNNoise 资源缺失: ${RNNOISE_RESOURCE_DIR}/librnnoise.dylib"
    echo "  error: 请先运行 ./scripts/setup-rnnoise.sh 并将结果提交到仓库"
    exit 1
fi
echo ""

# --- 4. 生成 Xcode 工程 ---
echo "--- Step 4: 生成 Xcode 工程 ---"
cd "${APP_DIR}"
xcodegen generate
echo "  ✓ Typoless.xcodeproj 已生成"
echo ""

echo "=== 构建准备完成 ✓ ==="
