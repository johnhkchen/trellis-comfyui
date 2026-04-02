#!/usr/bin/env bash
#
# Start ComfyUI on a GPU pod after setup was done on a CPU instance.
# Run this on the GPU pod with the same network volume attached.
#
set -euo pipefail

WORKSPACE="/workspace"
COMFY="$WORKSPACE/ComfyUI"

if [ ! -d "$COMFY" ]; then
    echo "Error: ComfyUI not found at $COMFY"
    echo "Run setup.sh on a CPU instance first."
    exit 1
fi

# Install CUDA-only deps that couldn't install on CPU
echo "Installing CUDA dependencies..."
pip install -q comfy-sparse-attn 2>/dev/null || echo "comfy-sparse-attn already installed or failed"

# Point HuggingFace at the pre-downloaded models
export HF_HOME="$WORKSPACE/hf_cache"

echo ""
echo "Starting ComfyUI..."
echo "  HF_HOME: $HF_HOME"
echo "  URL:     http://0.0.0.0:8188"
echo ""

cd "$COMFY"
python main.py --listen 0.0.0.0 --port 8188
