#!/usr/bin/env bash
# validate-whisper-bundle.sh — 校验构建产物中 Whisper 资源完整性
#
# 用法 (Xcode Build Phase 中):
#   "${SRCROOT}/../scripts/validate-whisper-bundle.sh"
#
# 本脚本在 Xcode 构建阶段运行，校验最终 .app 包中的 Whisper 资源是否完整。
# 校验失败时以 exit 1 中断构建。
#
# 需要以下 Xcode 构建变量:
#   BUILT_PRODUCTS_DIR       构建产物目录
#   CONTENTS_FOLDER_PATH     .app 内 Contents 相对路径

set -euo pipefail

BUNDLE_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}"
RESOURCES_DIR="${BUNDLE_DIR}/Resources"
WHISPER_BIN="${RESOURCES_DIR}/whisper/bin/whisper-cli"
WHISPER_MODEL="${RESOURCES_DIR}/whisper/models/ggml-small.bin"

has_errors=0

# 校验 whisper-cli 二进制
if [[ ! -f "${WHISPER_BIN}" ]]; then
    echo "error: Whisper CLI 未找到: ${WHISPER_BIN}"
    echo "  请先运行: ./scripts/setup-whisper.sh"
    has_errors=1
elif [[ ! -x "${WHISPER_BIN}" ]]; then
    echo "warning: whisper-cli 不可执行，正在修复权限..."
    chmod +x "${WHISPER_BIN}"
fi

# 校验模型文件
if [[ ! -f "${WHISPER_MODEL}" ]]; then
    echo "error: Whisper 模型未找到: ${WHISPER_MODEL}"
    echo "  请先运行: ./scripts/setup-whisper.sh"
    has_errors=1
elif [[ ! -s "${WHISPER_MODEL}" ]]; then
    echo "error: Whisper 模型文件为空: ${WHISPER_MODEL}"
    has_errors=1
fi

if [[ ${has_errors} -ne 0 ]]; then
    echo "error: Whisper 资源校验失败。构建产物将无法正常运行。"
    exit 1
fi

echo "Whisper 资源校验通过。"
