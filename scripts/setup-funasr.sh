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
#   - ct-punc (punctuation restoration)
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

# Download models using FunASR's model hub (downloads from ModelScope)
"$PYTHON" -c "
import os
import sys

model_dir = '$MODEL_DIR'

from funasr import AutoModel

# paraformer-zh (ASR)
asr_path = os.path.join(model_dir, 'paraformer-zh')
if not os.path.exists(asr_path):
    print('Downloading paraformer-zh ...')
    AutoModel(model='paraformer-zh', model_path=asr_path, disable_update=True)
    print('  Done.')
else:
    print('paraformer-zh already exists, skipping.')

# fsmn-vad (VAD)
vad_path = os.path.join(model_dir, 'fsmn-vad')
if not os.path.exists(vad_path):
    print('Downloading fsmn-vad ...')
    AutoModel(model='fsmn-vad', model_path=vad_path, disable_update=True)
    print('  Done.')
else:
    print('fsmn-vad already exists, skipping.')

# ct-punc (Punctuation)
punc_path = os.path.join(model_dir, 'ct-punc')
if not os.path.exists(punc_path):
    print('Downloading ct-punc ...')
    AutoModel(model='ct-punc', model_path=punc_path, disable_update=True)
    print('  Done.')
else:
    print('ct-punc already exists, skipping.')

print('All models ready.')
"

echo "==> FunASR model setup complete"
echo "    Models at: $MODEL_DIR"
