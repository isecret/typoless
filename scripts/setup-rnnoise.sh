#!/usr/bin/env bash
# setup-rnnoise.sh — 准备 Typoless 所需的 RNNoise 降噪库
#
# 用法:
#   ./scripts/setup-rnnoise.sh
#
# 本脚本将 RNNoise 动态库放置到 app/Typoless/Resources/rnnoise/ 下，
# 使 Xcode 构建时能将它们打包进 .app bundle。
#
# 环境变量:
#   RNNOISE_LIB_PATH    预编译 librnnoise.dylib 的本地路径
#
# 如未设置环境变量，脚本会尝试从 Homebrew 安装或本地编译。
#
# 目录约定:
#   rnnoise/
#   └── lib/
#       └── librnnoise.dylib
#
# 第三方来源:
#   RNNoise - https://gitlab.xiph.org/xiph/rnnoise
#   许可证: BSD-3-Clause

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RNNOISE_RESOURCE_DIR="${PROJECT_ROOT}/app/Typoless/Resources/rnnoise"
RNNOISE_LIB_DIR="${RNNOISE_RESOURCE_DIR}/lib"

echo "=== Typoless RNNoise 资源准备 ==="
echo ""

# 创建目录
mkdir -p "${RNNOISE_LIB_DIR}"

# 1. 检查环境变量
if [ -n "${RNNOISE_LIB_PATH:-}" ]; then
    echo "→ 使用环境变量指定的 RNNoise 库: ${RNNOISE_LIB_PATH}"

    if [ ! -f "${RNNOISE_LIB_PATH}" ]; then
        echo "error: RNNOISE_LIB_PATH 指定的文件不存在: ${RNNOISE_LIB_PATH}"
        exit 1
    fi

    cp "${RNNOISE_LIB_PATH}" "${RNNOISE_LIB_DIR}/librnnoise.dylib"
    echo "✓ RNNoise 库已复制"
else
    # 2. 尝试查找已安装的 RNNoise
    FOUND_LIB=""

    # Homebrew
    if command -v brew &>/dev/null; then
        BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
        if [ -f "${BREW_PREFIX}/lib/librnnoise.dylib" ]; then
            FOUND_LIB="${BREW_PREFIX}/lib/librnnoise.dylib"
        fi
    fi

    # 常见路径
    for path in /usr/local/lib/librnnoise.dylib /opt/homebrew/lib/librnnoise.dylib; do
        if [ -f "${path}" ] && [ -z "${FOUND_LIB}" ]; then
            FOUND_LIB="${path}"
        fi
    done

    if [ -n "${FOUND_LIB}" ]; then
        echo "→ 找到已安装的 RNNoise: ${FOUND_LIB}"
        cp "${FOUND_LIB}" "${RNNOISE_LIB_DIR}/librnnoise.dylib"
        echo "✓ RNNoise 库已复制"
    else
        echo ""
        echo "未找到 RNNoise 库。请通过以下方式之一准备："
        echo ""
        echo "  方式 1: 通过 Homebrew 安装"
        echo "    brew install rnnoise"
        echo "    然后重新运行本脚本"
        echo ""
        echo "  方式 2: 手动编译"
        echo "    git clone https://gitlab.xiph.org/xiph/rnnoise.git"
        echo "    cd rnnoise && ./autogen.sh && ./configure && make"
        echo "    export RNNOISE_LIB_PATH=\$(pwd)/.libs/librnnoise.dylib"
        echo "    然后重新运行本脚本"
        echo ""
        echo "  方式 3: 指定已编译的库路径"
        echo "    RNNOISE_LIB_PATH=/path/to/librnnoise.dylib ./scripts/setup-rnnoise.sh"
        echo ""
        exit 1
    fi
fi

# 验证
echo ""
echo "=== 验证 RNNoise 资源 ==="
PASS=true

if [ -f "${RNNOISE_LIB_DIR}/librnnoise.dylib" ]; then
    SIZE=$(stat -f%z "${RNNOISE_LIB_DIR}/librnnoise.dylib" 2>/dev/null || stat -c%s "${RNNOISE_LIB_DIR}/librnnoise.dylib" 2>/dev/null || echo "0")
    if [ "${SIZE}" -gt 0 ]; then
        echo "  ✓ librnnoise.dylib (${SIZE} bytes)"
    else
        echo "  ✗ librnnoise.dylib 为空"
        PASS=false
    fi
else
    echo "  ✗ librnnoise.dylib 缺失"
    PASS=false
fi

if $PASS; then
    echo ""
    echo "=== RNNoise 资源准备完成 ✓ ==="
else
    echo ""
    echo "=== RNNoise 资源准备失败 ✗ ==="
    exit 1
fi
