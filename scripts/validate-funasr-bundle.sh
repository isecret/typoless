#!/usr/bin/env bash
# validate-funasr-bundle.sh — 校验构建产物中 FunASR 资源完整性
#
# 用法 (Xcode Build Phase 中):
#   "${SRCROOT}/../scripts/validate-funasr-bundle.sh"
#
# 本脚本在 Xcode 构建阶段运行，校验最终 .app 包中的 FunASR 资源是否完整。
# 校验失败时以 exit 1 中断构建。
#
# 需要以下 Xcode 构建变量:
#   BUILT_PRODUCTS_DIR       构建产物目录
#   CONTENTS_FOLDER_PATH     .app 内 Contents 相对路径

set -euo pipefail

BUNDLE_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}"
RESOURCES_DIR="${BUNDLE_DIR}/Resources"
FUNASR_BIN="${RESOURCES_DIR}/funasr/bin/funasr-cli"
FUNASR_MODELS="${RESOURCES_DIR}/funasr/models"

has_errors=0

# 校验 funasr-cli 二进制
if [[ ! -f "${FUNASR_BIN}" ]]; then
    echo "error: FunASR 二进制未找到: ${FUNASR_BIN}"
    echo "  请先运行: ./scripts/setup-funasr.sh"
    has_errors=1
elif [[ ! -x "${FUNASR_BIN}" ]]; then
    echo "warning: funasr-cli 不可执行，正在修复权限..."
    chmod +x "${FUNASR_BIN}"
fi

# 校验模型目录
if [[ ! -d "${FUNASR_MODELS}" ]]; then
    echo "error: FunASR 模型目录未找到: ${FUNASR_MODELS}"
    echo "  请先运行: ./scripts/setup-funasr.sh"
    has_errors=1
else
    for model in paraformer vad punc; do
        model_path="${FUNASR_MODELS}/${model}"
        if [[ ! -d "${model_path}" ]]; then
            echo "error: 模型 '${model}' 未找到: ${model_path}"
            has_errors=1
        else
            onnx_count=$(find "${model_path}" \( -name '*.onnx' -o -name '*.bin' \) 2>/dev/null | wc -l | tr -d ' ')
            if [[ "${onnx_count}" -eq 0 ]]; then
                echo "error: 模型 '${model}' 目录为空（无 .onnx/.bin 文件）"
                has_errors=1
            fi
        fi
    done
fi

if [[ ${has_errors} -ne 0 ]]; then
    echo "error: FunASR 资源校验失败。构建产物将无法正常运行。"
    exit 1
fi

echo "FunASR 资源校验通过。"
