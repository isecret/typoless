#!/usr/bin/env bash
# setup-sherpa.sh — 准备 Typoless 所需的 sherpa-onnx runtime 与中文 streaming 模型
#
# 用法:
#   ./scripts/setup-sherpa.sh
#
# 本脚本将 sherpa-onnx 运行时库和中文 streaming transducer 模型放置到
# app/Typoless/Resources/sherpa/ 下，使 Xcode 构建时能将它们打包进 .app bundle。
#
# 环境变量:
#   SHERPA_LIB_PATH       预编译 libsherpa-onnx-c-api.dylib 的本地路径
#   SHERPA_MODEL_DIR      模型目录路径（包含 encoder/decoder/joiner/tokens）
#
# 目录约定:
#   sherpa/
#   ├── lib/
#   │   └── libsherpa-onnx-c-api.dylib
#   └── models/
#       └── streaming-zh/
#           ├── encoder.onnx (or encoder.int8.onnx)
#           ├── decoder.onnx (or decoder.int8.onnx)
#           ├── joiner.onnx  (or joiner.int8.onnx)
#           └── tokens.txt
#
# 第三方来源:
#   sherpa-onnx - https://github.com/k2-fsa/sherpa-onnx
#   许可证: Apache-2.0
#
# 推荐模型:
#   sherpa-onnx-streaming-zipformer-zh-14M (小尺寸中文流式模型)
#   https://github.com/k2-fsa/sherpa-onnx/releases

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SHERPA_RESOURCE_DIR="${PROJECT_ROOT}/app/Typoless/Resources/sherpa"
SHERPA_LIB_DIR="${SHERPA_RESOURCE_DIR}/lib"
SHERPA_MODEL_DIR_DEST="${SHERPA_RESOURCE_DIR}/models/streaming-zh"

echo "=== Typoless sherpa-onnx 资源准备 ==="
echo ""

# 创建目录
mkdir -p "${SHERPA_LIB_DIR}"
mkdir -p "${SHERPA_MODEL_DIR_DEST}"

# 1. 准备 runtime 库
echo "--- 1. sherpa-onnx runtime 库 ---"

if [ -n "${SHERPA_LIB_PATH:-}" ]; then
    echo "→ 使用环境变量指定的 sherpa-onnx 库: ${SHERPA_LIB_PATH}"

    if [ ! -f "${SHERPA_LIB_PATH}" ]; then
        echo "error: SHERPA_LIB_PATH 指定的文件不存在: ${SHERPA_LIB_PATH}"
        exit 1
    fi

    cp "${SHERPA_LIB_PATH}" "${SHERPA_LIB_DIR}/libsherpa-onnx-c-api.dylib"
    echo "✓ sherpa-onnx 库已复制"
else
    # 尝试查找已安装的 sherpa-onnx
    FOUND_LIB=""

    for path in \
        /usr/local/lib/libsherpa-onnx-c-api.dylib \
        /opt/homebrew/lib/libsherpa-onnx-c-api.dylib \
        "${HOME}/.local/lib/libsherpa-onnx-c-api.dylib"; do
        if [ -f "${path}" ] && [ -z "${FOUND_LIB}" ]; then
            FOUND_LIB="${path}"
        fi
    done

    if [ -n "${FOUND_LIB}" ]; then
        echo "→ 找到已安装的 sherpa-onnx: ${FOUND_LIB}"
        cp "${FOUND_LIB}" "${SHERPA_LIB_DIR}/libsherpa-onnx-c-api.dylib"
        echo "✓ sherpa-onnx 库已复制"
    else
        echo ""
        echo "未找到 sherpa-onnx runtime 库。请通过以下方式准备："
        echo ""
        echo "  方式 1: 从 GitHub Release 下载预编译库"
        echo "    https://github.com/k2-fsa/sherpa-onnx/releases"
        echo "    下载 macOS arm64 版本，解压后设置环境变量:"
        echo "    SHERPA_LIB_PATH=/path/to/libsherpa-onnx-c-api.dylib"
        echo ""
        echo "  方式 2: 从源码编译"
        echo "    git clone https://github.com/k2-fsa/sherpa-onnx"
        echo "    cd sherpa-onnx && mkdir build && cd build"
        echo "    cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON .."
        echo "    make -j\$(sysctl -n hw.ncpu)"
        echo "    SHERPA_LIB_PATH=\$(pwd)/lib/libsherpa-onnx-c-api.dylib"
        echo ""
        exit 1
    fi
fi

# 2. 准备模型
echo ""
echo "--- 2. 中文 streaming transducer 模型 ---"

if [ -n "${SHERPA_MODEL_DIR:-}" ]; then
    echo "→ 使用环境变量指定的模型目录: ${SHERPA_MODEL_DIR}"

    if [ ! -d "${SHERPA_MODEL_DIR}" ]; then
        echo "error: SHERPA_MODEL_DIR 指定的目录不存在: ${SHERPA_MODEL_DIR}"
        exit 1
    fi

    # 复制模型文件
    for pattern in encoder*.onnx decoder*.onnx joiner*.onnx tokens.txt; do
        found=false
        for f in "${SHERPA_MODEL_DIR}"/${pattern}; do
            if [ -f "$f" ]; then
                cp "$f" "${SHERPA_MODEL_DIR_DEST}/"
                echo "  ✓ $(basename "$f")"
                found=true
            fi
        done
    done
    echo "✓ 模型文件已复制"
else
    # 检查目标目录是否已有模型
    if [ -f "${SHERPA_MODEL_DIR_DEST}/tokens.txt" ]; then
        echo "→ 模型目录已存在，跳过"
    else
        echo ""
        echo "未指定模型目录。请通过以下方式准备："
        echo ""
        echo "  1. 下载推荐模型："
        echo "    https://github.com/k2-fsa/sherpa-onnx/releases"
        echo "    推荐: sherpa-onnx-streaming-zipformer-zh-14M"
        echo ""
        echo "  2. 解压后设置环境变量:"
        echo "    SHERPA_MODEL_DIR=/path/to/model-dir ./scripts/setup-sherpa.sh"
        echo ""
        echo "  模型目录应包含: encoder.onnx, decoder.onnx, joiner.onnx, tokens.txt"
        echo ""
        exit 1
    fi
fi

# 3. 验证
echo ""
echo "=== 验证 sherpa-onnx 资源 ==="
PASS=true

check_file() {
    local file=$1
    local label=$2
    if [ -f "${file}" ]; then
        SIZE=$(stat -f%z "${file}" 2>/dev/null || stat -c%s "${file}" 2>/dev/null || echo "0")
        if [ "${SIZE}" -gt 0 ]; then
            echo "  ✓ ${label} (${SIZE} bytes)"
        else
            echo "  ✗ ${label} 为空"
            PASS=false
        fi
    else
        echo "  ✗ ${label} 缺失"
        PASS=false
    fi
}

check_file "${SHERPA_LIB_DIR}/libsherpa-onnx-c-api.dylib" "libsherpa-onnx-c-api.dylib"

# 模型文件检查（支持 int8 变体）
ENCODER_FOUND=false
for f in "${SHERPA_MODEL_DIR_DEST}"/encoder*.onnx; do
    if [ -f "$f" ]; then ENCODER_FOUND=true; check_file "$f" "$(basename "$f")"; break; fi
done
$ENCODER_FOUND || { echo "  ✗ encoder.onnx 缺失"; PASS=false; }

DECODER_FOUND=false
for f in "${SHERPA_MODEL_DIR_DEST}"/decoder*.onnx; do
    if [ -f "$f" ]; then DECODER_FOUND=true; check_file "$f" "$(basename "$f")"; break; fi
done
$DECODER_FOUND || { echo "  ✗ decoder.onnx 缺失"; PASS=false; }

JOINER_FOUND=false
for f in "${SHERPA_MODEL_DIR_DEST}"/joiner*.onnx; do
    if [ -f "$f" ]; then JOINER_FOUND=true; check_file "$f" "$(basename "$f")"; break; fi
done
$JOINER_FOUND || { echo "  ✗ joiner.onnx 缺失"; PASS=false; }

check_file "${SHERPA_MODEL_DIR_DEST}/tokens.txt" "tokens.txt"

if $PASS; then
    echo ""
    echo "=== sherpa-onnx 资源准备完成 ✓ ==="
else
    echo ""
    echo "=== sherpa-onnx 资源准备不完整 ✗ ==="
    exit 1
fi
