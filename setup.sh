#!/usr/bin/env bash
#
# TRELLIS.2 ComfyUI setup for RunPod
# Run this inside the RunPod pod after deploying with the ComfyUI template.
#
set -euo pipefail

# Auto-detect ComfyUI path (RunPod templates vary)
if [ -n "${COMFYUI_DIR:-}" ]; then
    :
elif [ -d "/workspace/runpod-slim/ComfyUI" ]; then
    COMFYUI_DIR="/workspace/runpod-slim/ComfyUI"
elif [ -d "/workspace/ComfyUI" ]; then
    COMFYUI_DIR="/workspace/ComfyUI"
else
    echo "Error: Cannot find ComfyUI installation."
    echo "Set COMFYUI_DIR manually: COMFYUI_DIR=/path/to/ComfyUI bash setup.sh"
    exit 1
fi
NODE_DIR="$COMFYUI_DIR/custom_nodes/ComfyUI-Trellis2"

echo "============================================"
echo "  TRELLIS.2 ComfyUI Setup for RunPod"
echo "============================================"
echo ""
echo "ComfyUI directory: $COMFYUI_DIR"
echo ""

# ── Step 1: Install the ComfyUI-Trellis2 custom node ──
if [ -d "$NODE_DIR" ]; then
    echo "[1/5] ComfyUI-Trellis2 node already installed, pulling latest..."
    cd "$NODE_DIR" && git pull && cd -
else
    echo "[1/5] Cloning ComfyUI-Trellis2..."
    git clone https://github.com/visualbruno/ComfyUI-Trellis2.git "$NODE_DIR"
fi

# ── Step 2: Install binary wheels (CUDA-dependent, order matters) ──
echo "[2/5] Installing binary dependencies..."

# Detect PyTorch version for correct wheel directory
TORCH_VERSION=$(python3 -c "import torch; v=torch.__version__; print('Torch291' if v.startswith('2.9') else 'Torch270' if v.startswith('2.7') else 'Torch260')" 2>/dev/null || echo "Torch291")
WHEEL_DIR="$NODE_DIR/wheels/Linux/$TORCH_VERSION"

if [ ! -d "$WHEEL_DIR" ]; then
    echo "  Warning: No wheels for $TORCH_VERSION, trying Torch291..."
    WHEEL_DIR="$NODE_DIR/wheels/Linux/Torch291"
fi

if [ -d "$WHEEL_DIR" ]; then
    echo "  Using wheels from: $WHEEL_DIR"
    pip install "$WHEEL_DIR"/cumesh-*.whl 2>/dev/null || echo "  cumesh wheel not found, skipping"
    pip install "$WHEEL_DIR"/nvdiffrast-*.whl 2>/dev/null || echo "  nvdiffrast wheel not found, skipping"
    pip install "$WHEEL_DIR"/nvdiffrec_render-*.whl 2>/dev/null || echo "  nvdiffrec_render wheel not found, skipping"
    pip install "$WHEEL_DIR"/flex_gemm-*.whl 2>/dev/null || echo "  flex_gemm wheel not found, skipping"
    pip install "$WHEEL_DIR"/o_voxel-*.whl 2>/dev/null || echo "  o_voxel wheel not found, skipping"
else
    echo "  ERROR: No wheel directory found at $WHEEL_DIR"
    echo "  You may need to build wheels manually."
fi

# Python requirements
echo "  Installing Python requirements..."
pip install -r "$NODE_DIR/requirements.txt" -q

# ── Step 3: Download TRELLIS.2-4B model ──
echo "[3/5] Downloading TRELLIS.2-4B model (~16 GB, this takes a while)..."

MODEL_DIR="$COMFYUI_DIR/models/microsoft/TRELLIS.2-4B"
mkdir -p "$MODEL_DIR/ckpts"

CKPT_BASE="https://huggingface.co/microsoft/TRELLIS.2-4B/resolve/main/ckpts"
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
    DEST_FILE="$MODEL_DIR/ckpts/${ckpt}.safetensors"
    if [ -f "$DEST_FILE" ]; then
        echo "  Skipping $ckpt (already exists)"
    else
        echo "  Downloading $ckpt..."
        wget -q --show-progress "$CKPT_BASE/${ckpt}.safetensors" -O "$DEST_FILE"
    fi
    # Also download the .json config if it exists
    JSON_FILE="$MODEL_DIR/ckpts/${ckpt}.json"
    if [ ! -f "$JSON_FILE" ]; then
        wget -q "$CKPT_BASE/${ckpt}.json" -O "$JSON_FILE" 2>/dev/null || true
    fi
done

# Pipeline configs
for cfg in pipeline.json texturing_pipeline.json; do
    if [ ! -f "$MODEL_DIR/$cfg" ]; then
        echo "  Downloading $cfg..."
        wget -q "https://huggingface.co/microsoft/TRELLIS.2-4B/resolve/main/$cfg" -O "$MODEL_DIR/$cfg"
    fi
done

# ── Step 4: Download DINOv3 (required, hard error if missing) ──
echo "[4/5] Downloading DINOv3 model (~1.2 GB)..."

DINO_DIR="$COMFYUI_DIR/models/facebook/dinov3-vitl16-pretrain-lvd1689m"
mkdir -p "$DINO_DIR"

if [ ! -f "$DINO_DIR/model.safetensors" ]; then
    wget -q --show-progress \
        "https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m/resolve/main/model.safetensors" \
        -O "$DINO_DIR/model.safetensors"
else
    echo "  DINOv3 already downloaded"
fi

# ── Step 5: Set environment variables ──
echo "[5/5] Setting environment variables..."

ENV_FILE="/etc/environment"
grep -q "OPENCV_IO_ENABLE_OPENEXR" "$ENV_FILE" 2>/dev/null || {
    echo 'OPENCV_IO_ENABLE_OPENEXR=1' >> "$ENV_FILE"
    echo 'PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True' >> "$ENV_FILE"
    echo 'ATTN_BACKEND=flash_attn' >> "$ENV_FILE"
}

export OPENCV_IO_ENABLE_OPENEXR=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export ATTN_BACKEND=flash_attn

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "Models downloaded to: $MODEL_DIR"
echo "Node installed to:    $NODE_DIR"
echo ""
echo "Next steps:"
echo "  1. Restart ComfyUI (or restart the pod)"
echo "  2. Load workflow.json in the ComfyUI browser UI"
echo "  3. Upload an image and click Queue Prompt"
echo "  4. GLB files will appear in $COMFYUI_DIR/output/"
echo ""
