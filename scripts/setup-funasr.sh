#!/usr/bin/env bash
# setup-funasr.sh — Download FunASR models to the project resource directory.
#
# Usage:
#   ./scripts/setup-funasr.sh
#
# Environment variables:
#   FUNASR_MODEL_DIR  Override model output directory
#                     Default: app/Typoless/Resources/funasr/models
#
# Models downloaded:
#   - paraformer-zh (speech recognition)
#   - fsmn-vad (voice activity detection)
#
# Source: ModelScope / FunASR official models
# License: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODEL_DIR="${FUNASR_MODEL_DIR:-$PROJECT_ROOT/app/Typoless/Resources/funasr/models}"

echo "==> FunASR model setup"
echo "    Model directory: $MODEL_DIR"

# Check Python availability
PYTHON="${FUNASR_PYTHON_PATH:-python3}"
if ! command -v "$PYTHON" &>/dev/null; then
    echo "ERROR: Python 3 not found. Install Python 3 or set FUNASR_PYTHON_PATH."
    exit 1
fi

# Check funasr is installed
if ! "$PYTHON" -c "import funasr" 2>/dev/null; then
    echo "WARNING: funasr package not installed. Installing..."
    "$PYTHON" -m pip install funasr torch torchaudio --quiet
fi

mkdir -p "$MODEL_DIR"

# Download models using ModelScope snapshot_download.
"$PYTHON" -c "
import os
import sys

model_dir = '$MODEL_DIR'

from modelscope.hub.snapshot_download import snapshot_download

MODELS = [
    (
        'paraformer-zh',
        'iic/speech_seaco_paraformer_large_asr_nat-zh-cn-16k-common-vocab8404-pytorch',
    ),
    (
        'fsmn-vad',
        'iic/speech_fsmn_vad_zh-cn-16k-common-pytorch',
    ),
]

for local_name, repo_id in MODELS:
    target_path = os.path.join(model_dir, local_name)
    if os.path.exists(target_path) and os.listdir(target_path):
        print(f'{local_name} already exists, skipping.')
        continue

    print(f'Downloading {local_name} from {repo_id} ...')
    os.makedirs(target_path, exist_ok=True)
    snapshot_download(
        repo_id,
        cache_dir=model_dir,
        local_dir=target_path,
        local_files_only=False,
    )
    print('  Done.')

print('All models ready.')
"

echo "==> FunASR model setup complete"
echo "    Models at: $MODEL_DIR"
