#!/usr/bin/env bash
#
# Upload images / download .glb files via RunPod S3 API.
# No GPU pod needed for file transfer — works directly with the network volume.
#
# Usage:
#   ./s3.sh setup-models              # Download TRELLIS.2 models to volume (no GPU needed, ~17 GB)
#   ./s3.sh upload ./images/          # Upload images before starting GPU pod
#   ./s3.sh download [output-dir]     # Download .glb results after processing
#   ./s3.sh ls [path]                 # List files on the volume
#
# Environment:
#   RUNPOD_BUCKET   - S3 bucket name (default: hl1vwr8frk)
#   RUNPOD_REGION   - Region (default: us-il-1)
#   RUNPOD_ENDPOINT - S3 endpoint (default: https://s3api-us-il-1.runpod.io)
#
set -euo pipefail

BUCKET="${RUNPOD_BUCKET:-hl1vwr8frk}"
REGION="${RUNPOD_REGION:-us-il-1}"
ENDPOINT="${RUNPOD_ENDPOINT:-https://s3api-${REGION}.runpod.io}"
S3_BASE="s3://${BUCKET}"

# Paths on the network volume (mounted at /workspace in the pod)
IMAGES_PATH="ComfyUI/input"
OUTPUT_PATH="ComfyUI/output"

PROFILE="${AWS_PROFILE:-runpod}"

s3() {
    aws s3 "$@" --profile "$PROFILE" --region "$REGION" --endpoint-url "$ENDPOINT"
}

cmd_upload() {
    local input_dir="${1:?Usage: ./s3.sh upload <image-dir>}"

    if [ ! -d "$input_dir" ]; then
        echo "Error: $input_dir is not a directory"
        exit 1
    fi

    local count
    count=$(find "$input_dir" -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) | wc -l | tr -d ' ')
    echo "Uploading $count images to ${S3_BASE}/${IMAGES_PATH}/"
    echo "  (no GPU pod needed — writing directly to network volume)"
    echo ""

    s3 sync "$input_dir" "${S3_BASE}/${IMAGES_PATH}/" \
        --exclude '*' \
        --include '*.png' --include '*.jpg' --include '*.jpeg' --include '*.webp'

    echo ""
    echo "Done. Start your GPU pod and run:"
    echo "  python3 /workspace/trellis-setup/batch.py /workspace/${IMAGES_PATH}/"
}

cmd_download() {
    local output_dir="${1:-./generated}"
    mkdir -p "$output_dir"

    echo "Downloading .glb files from ${S3_BASE}/${OUTPUT_PATH}/ → $output_dir/"
    echo "  (no GPU pod needed — reading directly from network volume)"
    echo ""

    s3 sync "${S3_BASE}/${OUTPUT_PATH}/" "$output_dir/" \
        --exclude '*' \
        --include '*.glb'

    echo ""
    echo "Downloaded files:"
    ls -lh "$output_dir"/*.glb 2>/dev/null || echo "  (none)"
}

cmd_ls() {
    local path="${1:-}"
    s3 ls "${S3_BASE}/${path}"
}

cmd_setup_models() {
    echo "============================================"
    echo "  Downloading TRELLIS.2 models to network volume"
    echo "  (~17 GB — no GPU pod needed)"
    echo "============================================"
    echo ""

    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    local CACHE_DIR="$SCRIPT_DIR/.model-cache"

    local MODEL_DIR="$CACHE_DIR/microsoft/TRELLIS.2-4B"
    mkdir -p "$MODEL_DIR/ckpts"

    local HF_BASE="https://huggingface.co/microsoft/TRELLIS.2-4B/resolve/main"
    local CKPTS=(
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

    echo "[1/3] Downloading TRELLIS.2-4B checkpoints (skipping existing)..."
    for ckpt in "${CKPTS[@]}"; do
        local dest="$MODEL_DIR/ckpts/${ckpt}.safetensors"
        if [ -f "$dest" ]; then
            echo "  SKIP $ckpt.safetensors (cached)"
        else
            echo "  GET  $ckpt.safetensors"
            curl -SL "$HF_BASE/ckpts/${ckpt}.safetensors" -o "$dest"
        fi
        curl -sSL "$HF_BASE/ckpts/${ckpt}.json" -o "$MODEL_DIR/ckpts/${ckpt}.json" 2>/dev/null || true
    done

    for cfg in pipeline.json texturing_pipeline.json; do
        if [ ! -f "$MODEL_DIR/$cfg" ]; then
            echo "  GET  $cfg"
            curl -sSL "$HF_BASE/$cfg" -o "$MODEL_DIR/$cfg"
        fi
    done

    echo ""
    echo "[2/3] Downloading DINOv3 (skipping if cached)..."
    local DINO_DIR="$CACHE_DIR/facebook/dinov3-vitl16-pretrain-lvd1689m"
    mkdir -p "$DINO_DIR"
    if [ -f "$DINO_DIR/model.safetensors" ]; then
        echo "  SKIP model.safetensors (cached)"
    else
        echo "  GET  model.safetensors"
        curl -SL "https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m/resolve/main/model.safetensors" \
            -o "$DINO_DIR/model.safetensors"
    fi

    echo ""
    echo "[3/3] Uploading to network volume (sync — skips unchanged files)..."
    s3 sync "$CACHE_DIR/microsoft/" "${S3_BASE}/ComfyUI/models/microsoft/"
    s3 sync "$CACHE_DIR/facebook/" "${S3_BASE}/ComfyUI/models/facebook/"

    echo ""
    echo "Done. Models are on the network volume."
    echo "When you start a GPU pod, setup.sh will skip downloads (files already present)."
}

case "${1:-help}" in
    upload)       shift; cmd_upload "$@" ;;
    download)     shift; cmd_download "$@" ;;
    ls)           shift; cmd_ls "$@" ;;
    setup-models) shift; cmd_setup_models "$@" ;;
    *)
        echo "Usage: ./s3.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  setup-models         Download TRELLIS.2 models to volume (~17 GB, no GPU needed)"
        echo "  upload <image-dir>   Upload images to network volume (no GPU needed)"
        echo "  download [out-dir]   Download .glb results (no GPU needed)"
        echo "  ls [path]            List files on the network volume"
        echo ""
        echo "Environment:"
        echo "  RUNPOD_BUCKET=$BUCKET"
        echo "  RUNPOD_REGION=$REGION"
        echo "  RUNPOD_ENDPOINT=$ENDPOINT"
        ;;
esac
