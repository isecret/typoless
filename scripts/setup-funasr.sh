#!/usr/bin/env bash
# setup-funasr.sh — 下载并准备 Typoless 所需的 FunASR 资源
#
# 用法:
#   ./scripts/setup-funasr.sh
#
# 本脚本将 FunASR 可执行文件和模型资源放置到 app/Typoless/Resources/funasr/ 下，
# 使 Xcode 构建时能将它们打包进 .app bundle。
#
# 环境变量:
#   FUNASR_CLI_PATH  预编译 funasr-cli 二进制的本地路径
#   FUNASR_CLI_URL   funasr-cli 二进制下载地址
#   SKIP_MODELS      设为 1 跳过模型下载
#
# 目录约定:
#   funasr/
#   ├── bin/
#   │   └── funasr-cli          # FunASR C++ offline CLI (macOS universal/arm64)
#   └── models/
#       ├── paraformer/          # 语音识别主模型 (paraformer-large ONNX)
#       ├── vad/                 # 语音端点检测模型 (FSMN-VAD ONNX)
#       └── punc/                # 标点恢复模型 (CT-Transformer ONNX)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RESOURCE_DIR="${PROJECT_ROOT}/app/Typoless/Resources/funasr"
BIN_DIR="${RESOURCE_DIR}/bin"
MODEL_DIR="${RESOURCE_DIR}/models"

# ModelScope 模型仓库地址
PARAFORMER_REPO="https://www.modelscope.cn/models/iic/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-onnx.git"
VAD_REPO="https://www.modelscope.cn/models/iic/speech_fsmn_vad_zh-cn-16k-common-onnx.git"
PUNC_REPO="https://www.modelscope.cn/models/iic/punc_ct-transformer_cn-en-common-vocab471067-large-onnx.git"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── 目录结构 ────────────────────────────────────────────────────────

setup_directories() {
    info "创建目录结构..."
    mkdir -p "${BIN_DIR}"
    mkdir -p "${MODEL_DIR}"
}

# ── funasr-cli 二进制 ───────────────────────────────────────────────

setup_binary() {
    local target="${BIN_DIR}/funasr-cli"

    if [[ -f "${target}" && -x "${target}" ]]; then
        info "funasr-cli 二进制已存在: ${target}"
        return 0
    fi

    # 方式 1: 通过 FUNASR_CLI_PATH 复制本地已编译的二进制
    if [[ -n "${FUNASR_CLI_PATH:-}" ]]; then
        if [[ -f "${FUNASR_CLI_PATH}" ]]; then
            info "从 ${FUNASR_CLI_PATH} 复制 funasr-cli..."
            cp "${FUNASR_CLI_PATH}" "${target}"
            chmod +x "${target}"
            info "funasr-cli 安装完成。"
            return 0
        else
            error "FUNASR_CLI_PATH 指向的文件不存在: ${FUNASR_CLI_PATH}"
            return 1
        fi
    fi

    # 方式 2: 通过 FUNASR_CLI_URL 下载
    if [[ -n "${FUNASR_CLI_URL:-}" ]]; then
        info "从 ${FUNASR_CLI_URL} 下载 funasr-cli..."
        if curl -fSL --progress-bar -o "${target}" "${FUNASR_CLI_URL}"; then
            chmod +x "${target}"
            info "funasr-cli 下载完成。"
            return 0
        else
            error "下载失败: ${FUNASR_CLI_URL}"
            return 1
        fi
    fi

    # 无可用来源 — 输出指引
    warn "funasr-cli 二进制未找到。"
    echo ""
    echo "  请通过以下方式之一提供 funasr-cli:"
    echo ""
    echo "  1. 指定本地已编译的二进制:"
    echo "     FUNASR_CLI_PATH=/path/to/funasr-cli ./scripts/setup-funasr.sh"
    echo ""
    echo "  2. 指定下载地址:"
    echo "     FUNASR_CLI_URL=https://example.com/funasr-cli ./scripts/setup-funasr.sh"
    echo ""
    echo "  3. 从源码编译 (FunASR C++ Runtime):"
    echo "     git clone https://github.com/modelscope/FunASR.git"
    echo "     cd FunASR/runtime/onnxruntime"
    echo "     mkdir build && cd build"
    echo "     cmake -DCMAKE_BUILD_TYPE=Release .."
    echo "     make -j\$(nproc)"
    echo "     # 将产物复制到: ${target}"
    echo ""
    echo "  4. 手动放置到:"
    echo "     ${target}"
    echo ""
    return 1
}

# ── 模型下载 ────────────────────────────────────────────────────────

download_model() {
    local name="$1"
    local repo_url="$2"
    local target_dir="${MODEL_DIR}/${name}"

    if [[ -d "${target_dir}" ]] && [[ -n "$(find "${target_dir}" -name '*.onnx' -o -name '*.bin' 2>/dev/null | head -1)" ]]; then
        info "模型 '${name}' 已存在，跳过下载。"
        return 0
    fi

    info "正在从 ModelScope 下载模型 '${name}'..."

    if ! command -v git-lfs &>/dev/null; then
        error "需要 git-lfs 来下载模型文件。请先安装:"
        echo "  brew install git-lfs && git lfs install"
        return 1
    fi

    rm -rf "${target_dir}"
    mkdir -p "${target_dir}"

    if git clone --depth 1 "${repo_url}" "${target_dir}" 2>&1; then
        # 清理 .git 目录节省空间
        rm -rf "${target_dir}/.git"
        info "模型 '${name}' 下载完成。"
        return 0
    else
        error "模型 '${name}' 下载失败。"
        rm -rf "${target_dir}"
        return 1
    fi
}

setup_models() {
    if [[ "${SKIP_MODELS:-0}" == "1" ]]; then
        warn "跳过模型下载 (SKIP_MODELS=1)"
        return 0
    fi

    info "开始下载 FunASR 模型..."
    local has_errors=0

    download_model "paraformer" "${PARAFORMER_REPO}" || has_errors=1
    download_model "vad" "${VAD_REPO}" || has_errors=1
    download_model "punc" "${PUNC_REPO}" || has_errors=1

    return ${has_errors}
}

# ── 校验 ────────────────────────────────────────────────────────────

validate() {
    local has_errors=0

    info "校验 FunASR 资源完整性..."

    # 校验二进制
    if [[ -f "${BIN_DIR}/funasr-cli" ]]; then
        if [[ -x "${BIN_DIR}/funasr-cli" ]]; then
            info "  ✓ funasr-cli 存在且可执行"
        else
            error "  ✗ funasr-cli 存在但不可执行"
            has_errors=1
        fi
    else
        error "  ✗ funasr-cli 不存在"
        has_errors=1
    fi

    # 校验每个模型的关键文件
    for model in paraformer vad punc; do
        local model_path="${MODEL_DIR}/${model}"
        if [[ -d "${model_path}" ]]; then
            local onnx_count
            onnx_count=$(find "${model_path}" \( -name '*.onnx' -o -name '*.bin' \) 2>/dev/null | wc -l | tr -d ' ')
            if [[ "${onnx_count}" -gt 0 ]]; then
                info "  ✓ 模型 '${model}' 已就绪 (${onnx_count} 个模型文件)"
            else
                error "  ✗ 模型 '${model}' 目录存在但无模型文件 (.onnx/.bin)"
                has_errors=1
            fi
        else
            error "  ✗ 模型 '${model}' 目录不存在"
            has_errors=1
        fi
    done

    return ${has_errors}
}

# ── Main ────────────────────────────────────────────────────────────

main() {
    info "=========================================="
    info " Typoless — FunASR 资源准备"
    info "=========================================="
    echo ""

    setup_directories

    local binary_ok=true
    setup_binary || binary_ok=false

    local models_ok=true
    setup_models || models_ok=false

    echo ""
    validate || true

    echo ""
    if [[ "${binary_ok}" == false || "${models_ok}" == false ]]; then
        warn "资源准备未完成，请根据上述提示补充缺失项后重新运行。"
        exit 1
    fi

    info "FunASR 资源准备完成！可以构建项目了。"
}

main "$@"
