#!/usr/bin/env bash
#
# TRELLIS.2 ComfyUI setup for RunPod (clean install)
#
# Tested on: RunPod slim ComfyUI template, RTX 4090, PyTorch 2.10+cu128
# Uses: PozzettiAndrea/ComfyUI-TRELLIS2 (pip-friendly, no binary wheels)
#
set -euo pipefail

# ── Detect ComfyUI ──
if [ -d "/workspace/runpod-slim/ComfyUI" ]; then
    COMFY="/workspace/runpod-slim/ComfyUI"
elif [ -d "/workspace/ComfyUI" ]; then
    COMFY="/workspace/ComfyUI"
else
    echo "Error: Cannot find ComfyUI. Set COMFY=/path/to/ComfyUI and re-run."
    exit 1
fi

# Use ComfyUI's own venv if it exists
if [ -f "$COMFY/.venv-cu128/bin/pip" ]; then
    PIP="$COMFY/.venv-cu128/bin/pip"
    PYTHON="$COMFY/.venv-cu128/bin/python"
else
    PIP="pip"
    PYTHON="python3"
fi

NODE_DIR="$COMFY/custom_nodes/ComfyUI-TRELLIS2"

echo "============================================"
echo "  TRELLIS.2 ComfyUI Setup (Clean)"
echo "============================================"
echo "  ComfyUI: $COMFY"
echo "  Python:  $($PYTHON --version 2>&1)"
echo "  Torch:   $($PYTHON -c 'import torch; print(torch.__version__)' 2>&1)"
echo "============================================"
echo ""

# ── Step 1: Remove old broken installs ──
echo "[1/4] Cleaning up old installs..."
rm -rf "$COMFY/custom_nodes/ComfyUI-Trellis2" 2>/dev/null || true
rm -rf "$COMFY/custom_nodes/ComfyUI-TRELLIS2" 2>/dev/null || true
echo "  Done"
echo ""

# ── Step 2: Install PozzettiAndrea's node ──
echo "[2/4] Installing ComfyUI-TRELLIS2 (PozzettiAndrea)..."
git clone https://github.com/PozzettiAndrea/ComfyUI-TRELLIS2.git "$NODE_DIR"
echo ""

# ── Step 3: Install Python dependencies ──
echo "[3/4] Installing dependencies..."
$PIP install -q \
    comfy-sparse-attn \
    trimesh \
    easydict \
    plyfile \
    zstandard \
    scipy \
    requests \
    "rembg[gpu]" \
    opencv-python

# Install the node's own requirements (if any remain)
if [ -f "$NODE_DIR/requirements.txt" ]; then
    $PIP install -q -r "$NODE_DIR/requirements.txt" 2>/dev/null || true
fi
echo "  Done"
echo ""

# ── Step 4: Verify ──
echo "[4/4] Verifying installation..."
$PYTHON -c "
import sys
errors = []
for mod in ['trimesh', 'easydict', 'plyfile', 'zstandard', 'scipy', 'requests', 'cv2']:
    try:
        __import__(mod)
        print(f'  OK: {mod}')
    except ImportError as e:
        print(f'  FAIL: {mod} — {e}')
        errors.append(mod)
if errors:
    print(f'\nWARNING: {len(errors)} modules failed to import')
else:
    print('\n  All dependencies OK')
"
echo ""

echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "  Node installed to: $NODE_DIR"
echo ""
echo "  Next steps:"
echo "    1. Restart ComfyUI (Manager > Restart, or restart the pod)"
echo "    2. Load workflow.json in the browser"
echo "    3. Upload an image and click Queue Prompt"
echo ""
echo "  Models will auto-download on first run from HuggingFace."
echo "  Or pre-download via: ./s3.sh setup-models"
echo ""
