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

HF_TOKEN="${HF_TOKEN:-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}"
HF_AUTH="Authorization: Bearer $HF_TOKEN"

MODEL_DIR="$WORKSPACE/models/microsoft/TRELLIS.2-4B"
mkdir -p "$MODEL_DIR/ckpts"

HF_BASE="https://huggingface.co/microsoft/TRELLIS.2-4B/resolve/main"
CKPTS=(
    "shape_enc_next_dc_f16c32_fp16"
    "shape_dec_next_dc_f16c32_fp16"
    "tex_enc_next_dc_f16c32_fp16"
    "tex_dec_next_dc_f16c32_fp16"
    "ss_flow_img_dit_1_3B_64_bf16"
    "slat_flow_img2shape_dit_1_3B_512_bf16"
    "slat_flow_img2shape_dit_1_3B_1024_bf16"
    "slat_flow_imgshape2tex_dit_1_3B_512_bf16"
    "slat_flow_imgshape2tex_dit_1_3B_1024_bf16"
)

for ckpt in "${CKPTS[@]}"; do
    dest="$MODEL_DIR/ckpts/${ckpt}.safetensors"
    if [ -f "$dest" ]; then
        echo "  SKIP $ckpt.safetensors"
    else
        echo "  GET  $ckpt.safetensors"
        wget -q --show-progress --header="$HF_AUTH" \
            "$HF_BASE/ckpts/${ckpt}.safetensors" -O "$dest"
    fi
    wget -q --header="$HF_AUTH" \
        "$HF_BASE/ckpts/${ckpt}.json" -O "$MODEL_DIR/ckpts/${ckpt}.json" 2>/dev/null || true
done

for cfg in pipeline.json texturing_pipeline.json; do
    [ -f "$MODEL_DIR/$cfg" ] || wget -q --header="$HF_AUTH" "$HF_BASE/$cfg" -O "$MODEL_DIR/$cfg"
done

echo ""
echo "  Downloading DINOv3..."
DINO_DIR="$WORKSPACE/models/facebook/dinov3-vitl16-pretrain-lvd1689m"
mkdir -p "$DINO_DIR"
if [ -f "$DINO_DIR/model.safetensors" ]; then
    echo "  SKIP model.safetensors"
else
    wget -q --show-progress --header="$HF_AUTH" \
        "https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m/resolve/main/model.safetensors" \
        -O "$DINO_DIR/model.safetensors"
fi
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
