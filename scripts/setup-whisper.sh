#!/usr/bin/env bash
# setup-whisper.sh — 准备 Typoless 所需的 whisper.cpp 资源
#
# 用法:
#   ./scripts/setup-whisper.sh
#
# 本脚本将 whisper-cli 可执行文件和模型文件放置到 app/Typoless/Resources/whisper/ 下，
# 使 Xcode 构建时能将它们打包进 .app bundle。
#
# 环境变量:
#   WHISPER_CLI_PATH    预编译 whisper-cli 二进制的本地路径
#   WHISPER_MODEL_PATH  ggml-small.bin 模型文件的本地路径
#
# 目录约定:
#   whisper/
#   ├── bin/
#   │   └── whisper-cli          # whisper.cpp CLI (macOS arm64/universal)
#   └── models/
#       └── ggml-small.bin       # Whisper small 模型 (ggml 格式)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RESOURCE_DIR="${PROJECT_ROOT}/app/Typoless/Resources/whisper"
BIN_DIR="${RESOURCE_DIR}/bin"
MODEL_DIR="${RESOURCE_DIR}/models"

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

# ── whisper-cli 二进制 ──────────────────────────────────────────────

setup_binary() {
    local target="${BIN_DIR}/whisper-cli"

    if [[ -f "${target}" && -x "${target}" ]]; then
        info "whisper-cli 二进制已存在: ${target}"
        return 0
    fi

    if [[ -n "${WHISPER_CLI_PATH:-}" ]]; then
        if [[ -f "${WHISPER_CLI_PATH}" ]]; then
            info "从 ${WHISPER_CLI_PATH} 复制 whisper-cli..."
            cp "${WHISPER_CLI_PATH}" "${target}"
            chmod +x "${target}"
            info "whisper-cli 安装完成。"
            return 0
        else
            error "WHISPER_CLI_PATH 指向的文件不存在: ${WHISPER_CLI_PATH}"
            return 1
        fi
    fi

    warn "whisper-cli 二进制未找到。"
    echo ""
    echo "  请通过以下方式之一提供 whisper-cli:"
    echo ""
    echo "  1. 指定本地已编译的二进制:"
    echo "     WHISPER_CLI_PATH=/path/to/whisper-cli ./scripts/setup-whisper.sh"
    echo ""
    echo "  2. 从源码编译 (whisper.cpp):"
    echo "     git clone https://github.com/ggerganov/whisper.cpp.git"
    echo "     cd whisper.cpp"
    echo "     cmake -B build -DCMAKE_BUILD_TYPE=Release"
    echo "     cmake --build build --config Release"
    echo "     # 将 build/bin/whisper-cli 复制到: ${target}"
    echo ""
    echo "  3. 通过 Homebrew 安装后复制:"
    echo "     brew install whisper-cpp"
    echo "     WHISPER_CLI_PATH=\$(which whisper-cpp) ./scripts/setup-whisper.sh"
    echo ""
    echo "  4. 手动放置到:"
    echo "     ${target}"
    echo ""
    return 1
}

# ── 模型文件 ────────────────────────────────────────────────────────

setup_model() {
    local target="${MODEL_DIR}/ggml-small.bin"

    if [[ -f "${target}" ]] && [[ -s "${target}" ]]; then
        info "模型文件已存在: ${target}"
        return 0
    fi

    if [[ -n "${WHISPER_MODEL_PATH:-}" ]]; then
        if [[ -f "${WHISPER_MODEL_PATH}" ]] && [[ -s "${WHISPER_MODEL_PATH}" ]]; then
            info "从 ${WHISPER_MODEL_PATH} 复制模型文件..."
            cp "${WHISPER_MODEL_PATH}" "${target}"
            info "模型文件安装完成。"
            return 0
        else
            error "WHISPER_MODEL_PATH 指向的文件不存在或为空: ${WHISPER_MODEL_PATH}"
            return 1
        fi
    fi

    warn "Whisper 模型文件未找到。"
    echo ""
    echo "  请通过以下方式之一提供 ggml-small.bin:"
    echo ""
    echo "  1. 指定本地模型文件路径:"
    echo "     WHISPER_MODEL_PATH=/path/to/ggml-small.bin ./scripts/setup-whisper.sh"
    echo ""
    echo "  2. 使用 whisper.cpp 官方脚本下载:"
    echo "     git clone https://github.com/ggerganov/whisper.cpp.git"
    echo "     cd whisper.cpp"
    echo "     bash models/download-ggml-model.sh small"
    echo "     # 将 models/ggml-small.bin 复制到: ${target}"
    echo ""
    echo "  3. 从 Hugging Face 下载:"
    echo "     curl -L -o ${target} \\"
    echo "       https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
    echo ""
    echo "  4. 手动放置到:"
    echo "     ${target}"
    echo ""
    return 1
}

# ── 校验 ────────────────────────────────────────────────────────────

validate() {
    local has_errors=0

    info "校验 Whisper 资源完整性..."

    # 校验二进制
    local binary="${BIN_DIR}/whisper-cli"
    if [[ -f "${binary}" ]]; then
        if [[ -x "${binary}" ]]; then
            info "  ✓ whisper-cli 存在且可执行"
        else
            error "  ✗ whisper-cli 存在但不可执行"
            has_errors=1
        fi
    else
        error "  ✗ whisper-cli 不存在"
        has_errors=1
    fi

    # 校验模型文件
    local model="${MODEL_DIR}/ggml-small.bin"
    if [[ -f "${model}" ]]; then
        if [[ -s "${model}" ]]; then
            local size
            size=$(stat -f%z "${model}" 2>/dev/null || stat -c%s "${model}" 2>/dev/null || echo "unknown")
            info "  ✓ ggml-small.bin 已就绪 (${size} bytes)"
        else
            error "  ✗ ggml-small.bin 为空文件"
            has_errors=1
        fi
    else
        error "  ✗ ggml-small.bin 不存在"
        has_errors=1
    fi

    return ${has_errors}
}

# ── Main ────────────────────────────────────────────────────────────

main() {
    info "=========================================="
    info " Typoless — Whisper 资源准备"
    info "=========================================="
    echo ""

    setup_directories

    local binary_ok=true
    setup_binary || binary_ok=false

    local model_ok=true
    setup_model || model_ok=false

    echo ""
    validate || true

    echo ""
    if [[ "${binary_ok}" == false || "${model_ok}" == false ]]; then
        warn "资源准备未完成，请根据上述提示补充缺失项后重新运行。"
        exit 1
    fi

    info "Whisper 资源准备完成！可以构建项目了。"
}

main "$@"
