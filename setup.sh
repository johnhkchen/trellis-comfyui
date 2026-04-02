#!/usr/bin/env bash
#
# TRELLIS.2 ComfyUI setup for RunPod
#
# Run on a CPU instance attached to your network volume.
# Installs ComfyUI + TRELLIS.2 node + downloads models.
# Then stop this instance and start a GPU pod with the same volume.
#
# Uses: PozzettiAndrea/ComfyUI-TRELLIS2 (pip-friendly, no binary wheels)
#
set -euo pipefail

WORKSPACE="/workspace"
COMFY="$WORKSPACE/ComfyUI"

echo "============================================"
echo "  TRELLIS.2 Full Setup (CPU instance)"
echo "============================================"
echo ""

# ── Step 1: Install ComfyUI ──
if [ -d "$COMFY" ]; then
    echo "[1/5] ComfyUI already installed, pulling latest..."
    cd "$COMFY" && git pull && cd -
else
    echo "[1/5] Installing ComfyUI..."
    cd "$WORKSPACE"
    git clone https://github.com/comfyanonymous/ComfyUI.git
    cd "$COMFY"
    pip install -r requirements.txt -q
fi
echo ""

# ── Step 2: Install TRELLIS.2 node ──
NODE_DIR="$COMFY/custom_nodes/ComfyUI-TRELLIS2"
echo "[2/5] Installing ComfyUI-TRELLIS2 node..."
rm -rf "$NODE_DIR" 2>/dev/null || true
git clone https://github.com/PozzettiAndrea/ComfyUI-TRELLIS2.git "$NODE_DIR"

if [ -f "$NODE_DIR/requirements.txt" ]; then
    pip install -r "$NODE_DIR/requirements.txt" -q 2>/dev/null || true
fi
echo ""

# ── Step 3: Install Python dependencies ──
echo "[3/5] Installing Python dependencies..."
pip install -q \
    trimesh \
    easydict \
    plyfile \
    zstandard \
    scipy \
    requests \
    opencv-python \
    huggingface_hub

# rembg needs onnxruntime — try GPU version, fall back to CPU
pip install -q "rembg[gpu]" 2>/dev/null || pip install -q "rembg[cpu]" || true

# comfy-sparse-attn may need CUDA to install — skip on CPU, will install on GPU pod
pip install -q comfy-sparse-attn 2>/dev/null || echo "  NOTE: comfy-sparse-attn skipped (needs CUDA). Will install on GPU pod."
echo ""

# ── Step 4: Download models ──
echo "[4/5] Downloading TRELLIS.2-4B models (~17 GB)..."
python3 -c "
from huggingface_hub import snapshot_download
import os

cache_dir = os.path.join('$WORKSPACE', 'hf_cache')
os.makedirs(cache_dir, exist_ok=True)

print('  Downloading microsoft/TRELLIS.2-4B...')
snapshot_download('microsoft/TRELLIS.2-4B', cache_dir=cache_dir)

print('  Downloading facebook/dinov3-vitl16-pretrain-lvd1689m...')
snapshot_download('facebook/dinov3-vitl16-pretrain-lvd1689m', cache_dir=cache_dir)

print('  Done.')
"
echo ""

# ── Step 5: Verify ──
echo "[5/5] Verifying..."
echo "  ComfyUI: $COMFY"
echo "  Node:    $NODE_DIR"
echo "  Models:  $WORKSPACE/hf_cache"
echo ""

python3 -c "
for mod in ['trimesh', 'easydict', 'plyfile', 'zstandard', 'scipy', 'requests', 'cv2', 'huggingface_hub']:
    try:
        __import__(mod)
        print(f'  OK: {mod}')
    except ImportError as e:
        print(f'  FAIL: {mod} — {e}')
"
echo ""

echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "  Everything is on the network volume."
echo "  Stop this CPU instance and start a GPU pod"
echo "  with the same volume attached."
echo ""
echo "  On the GPU pod, run ComfyUI:"
echo "    export HF_HOME=$WORKSPACE/hf_cache"
echo "    cd $COMFY && python main.py --listen 0.0.0.0 --port 8188"
echo ""
echo "  If comfy-sparse-attn was skipped, install on GPU pod:"
echo "    pip install comfy-sparse-attn"
echo ""
