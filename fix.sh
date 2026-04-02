#!/usr/bin/env bash
#
# Fix TRELLIS.2 ComfyUI node installation issues on RunPod.
#
set -euo pipefail

COMFY="/workspace/runpod-slim/ComfyUI"
NODE_SRC="/workspace/ComfyUI/custom_nodes/ComfyUI-Trellis2"
NODE_DST="$COMFY/custom_nodes/ComfyUI-Trellis2"

echo "=== Fixing TRELLIS.2 Node Installation ==="
echo ""

# 1. Move node to correct ComfyUI directory
if [ -d "$NODE_SRC" ] && [ ! -d "$NODE_DST" ]; then
    echo "[1/4] Moving node to $COMFY/custom_nodes/..."
    mv "$NODE_SRC" "$NODE_DST"
elif [ -d "$NODE_DST" ]; then
    echo "[1/4] Node already in correct location"
else
    echo "[1/4] ERROR: Cannot find node at $NODE_SRC or $NODE_DST"
    exit 1
fi

# 2. Install missing o_voxel wheel
echo "[2/4] Installing missing o_voxel wheel..."
WHEEL=$(find "$NODE_DST/wheels/Linux/" -name "o_voxel*.whl" 2>/dev/null | head -1)
if [ -n "$WHEEL" ]; then
    pip install "$WHEEL"
else
    echo "  WARNING: o_voxel wheel not found, trying all wheels..."
    for whl in "$NODE_DST"/wheels/Linux/Torch*/o_voxel*.whl; do
        [ -f "$whl" ] && pip install "$whl" && break
    done
fi

# Verify
python3 -c "import o_voxel; print('  o_voxel: OK')" 2>&1 || echo "  o_voxel: STILL MISSING"

# 3. Fix rembg (needs onnxruntime)
echo "[3/4] Installing rembg with GPU support..."
pip install "rembg[gpu]" -q

# Fix pymeshlab OpenGL dependency
echo "  Installing libOpenGL..."
apt-get update -qq && apt-get install -y -qq libopengl0 > /dev/null 2>&1 || true

# 4. Symlink models if uploaded to wrong path
echo "[4/4] Checking model paths..."
if [ -d "/workspace/ComfyUI/models/microsoft" ] && [ ! -d "$COMFY/models/microsoft" ]; then
    echo "  Symlinking models from /workspace/ComfyUI/models/ → $COMFY/models/"
    ln -sf /workspace/ComfyUI/models/microsoft "$COMFY/models/microsoft"
    ln -sf /workspace/ComfyUI/models/facebook "$COMFY/models/facebook"
elif [ -d "$COMFY/models/microsoft" ]; then
    echo "  Models already in correct location"
else
    echo "  WARNING: Models not found. Run ./s3.sh setup-models"
fi

echo ""
echo "=== Fix complete. Restart ComfyUI: ==="
echo ""
echo "  pkill -f 'python.*main.py' || true"
echo "  cd $COMFY && python main.py --listen 0.0.0.0 --port 8188 &"
echo ""
